from pathlib import Path

from loris_bids_reader.files.scans import BidsScanTsvRow
from loris_bids_reader.meg.data_type import BidsMegAcquisition

from lib.config import get_eeg_viz_enabled_config
from lib.db.models.imaging_file_type import DbImagingFileType
from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.physio_output_type import DbPhysioOutputType
from lib.db.models.session import DbSession
from lib.db.queries.imaging_file_type import try_get_imaging_file_type_with_type
from lib.db.queries.physio import (
    try_get_physio_file_with_path,
    try_get_physio_modality_with_name,
    try_get_physio_output_type_with_name,
)
from lib.db.queries.physio_file import try_get_physio_file_with_hash
from lib.env import Env
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.channels import insert_bids_channels_file
from lib.import_bids_dataset.copy_files import archive_bids_directory, copy_bids_file, get_loris_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import insert_events_metadata_file
from lib.import_bids_dataset.events_tsv import insert_bids_events_file
from lib.logging import log, log_warning
from lib.physio.chunking import create_meg_signal_chunks
from lib.physio.events import FileSource
from lib.physio.file_parameters import insert_physio_file, insert_physio_file_parameter
from lib.util.crypto import compute_file_blake2b_hash
from lib.util.error import group_errors_tuple
from lib.util.path import add_path_extension


def import_bids_meg_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    acquisition: BidsMegAcquisition,
    scan_row: BidsScanTsvRow | None,
):
    # TODO: The file is actually a directory, it should be tared before proceeding to the hash.
    modality, output_type, file_type = group_errors_tuple(
        f"Error while checking database information for MEG acquisition '{acquisition.name}'.",
        lambda: get_check_bids_physio_modality(env, acquisition),
        lambda: get_check_bids_physio_output_type(env, args.type or 'raw'),
        lambda: get_check_bids_imaging_file_type(env),
        # lambda: get_check_bids_physio_file_hash(env, acquisition),
    )

    loris_file_path = add_path_extension(
        get_loris_file_path(import_env, session, acquisition, acquisition.ctf_path),
        'tar.gz',
    )

    loris_file = try_get_physio_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        import_env.ignored_files_count += 1
        return

    check_bids_meg_metadata_files(env, acquisition)

    physio_file = insert_physio_file(
        env,
        session,
        modality,
        output_type,
        loris_file_path,
        file_type.type,
        scan_row.get_acquisition_time() if scan_row is not None else None
    )

    # insert_physio_file_parameter(env, physio_file, 'physiological_json_file_blake2b_hash', file_hash)
    for name, value in acquisition.sidecar.data.items():
        insert_physio_file_parameter(env, physio_file, name, value)

    if acquisition.events is not None:
        insert_bids_events_file(env, import_env, physio_file, session, acquisition, acquisition.events)
        if acquisition.events.dictionary is not None:
            insert_events_metadata_file(env, FileSource(physio_file), acquisition.events.dictionary)

    if acquisition.channels is not None:
        insert_bids_channels_file(env, import_env, physio_file, session, acquisition, acquisition.channels)

    if import_env.loris_bids_path is not None:
        copy_bids_meg_files(import_env.loris_bids_path, session, acquisition)

    env.db.commit()

    log(env, f"MEG file succesfully imported with ID: {physio_file.id}.")

    if get_eeg_viz_enabled_config(env):
        log(env, "Creating visualization chunks...")
        create_meg_signal_chunks(env, physio_file, acquisition.ctf_path)

    env.db.commit()

    import_env.imported_files_count += 1


def check_bids_meg_metadata_files(env: Env, acquisition: BidsMegAcquisition):
    """
    Check for the presence of BIDS metadata files for the BIDS MEG acquisition and warn the user if
    that is not the case.
    """

    if acquisition.channels is None:
        log_warning(env, f"No channels file found for acquisition '{acquisition.name}'.")

    if acquisition.events is None:
        log_warning(env, f"No events file found for acquisition '{acquisition.name}'.")

    if acquisition.events is not None and acquisition.events.dictionary is not None:
        log_warning(env, f"No events dictionary file found for acquisition '{acquisition.name}'.")


def copy_bids_meg_files(loris_bids_path: Path, session: DbSession, acquisition: BidsMegAcquisition):
    """
    Copy the files of a BIDS MEG acquisition into a LORIS BIDS directory.
    """

    if acquisition.channels is not None:
        copy_bids_file(loris_bids_path, session, acquisition, acquisition.channels.path)

    if acquisition.events is not None:
        copy_bids_file(loris_bids_path, session, acquisition, acquisition.events.path)
        if acquisition.events.dictionary is not None:
            copy_bids_file(loris_bids_path, session, acquisition, acquisition.events.dictionary.path)

    archive_bids_directory(loris_bids_path, session, acquisition, acquisition.ctf_path)


def get_check_bids_physio_modality(env: Env, acquisition: BidsMegAcquisition) -> DbPhysioModality:
    """
    Get the modality of a BIDS acquisition, or raise an exception if it is not present in the database.
    """

    modality = try_get_physio_modality_with_name(env.db, acquisition.data_type.name)
    if modality is None:
        raise Exception(f"Modality not found for BIDS data type '{acquisition.data_type.name}'.")

    return modality


def get_check_bids_physio_output_type(env: Env, type: str) -> DbPhysioOutputType:
    """
    Get the output type of a BIDS acquisition, or raise an exception if it is not present in the database.
    """

    output_type = try_get_physio_output_type_with_name(env.db, type)
    if output_type is None:
        raise Exception(f"Output type not found for output '{type}'.")

    return output_type


def get_check_bids_imaging_file_type(env: Env) -> DbImagingFileType:
    """
    Get the MEG CTF imaging file type, or raise an exception if it is not present in the database.
    """

    file_type = try_get_imaging_file_type_with_type(env.db, 'ctf')
    if file_type is None:
        raise Exception("Imaging file type not found for file type 'ctf'.")

    return file_type


def get_check_bids_physio_file_hash(env: Env, acquisition: BidsMegAcquisition) -> str:
    """
    Compute the BLAKE2b hash of a MEG CTF file and raise an exception if that hash is already
    registered in the database.
    """

    file_hash = compute_file_blake2b_hash(acquisition.ctf_path)

    file = try_get_physio_file_with_hash(env.db, file_hash)
    if file is not None:
        raise Exception(f"Physiological file with hash '{file_hash}' already present in the database.")

    return file_hash
