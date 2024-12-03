from pathlib import Path

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from loris_utils.error import group_errors_tuple

from lib.config import get_eeg_viz_enabled_config
from lib.db.models.session import DbSession
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.env import Env
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.channels import insert_bids_channels_file
from lib.import_bids_dataset.copy_files import copy_loris_bids_file, get_loris_bids_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import insert_events_metadata_file
from lib.import_bids_dataset.events_tsv import insert_bids_events_file
from lib.import_bids_dataset.file_type import get_check_bids_imaging_file_type
from lib.import_bids_dataset.meg_channels import read_meg_channels
from lib.import_bids_dataset.physio import get_check_bids_physio_modality, get_check_bids_physio_output_type
from lib.logging import log, log_warning
from lib.physio.chunking import create_physio_channels_chunks
from lib.physio.events import FileSource
from lib.physio.file import insert_physio_file
from lib.physio.parameters import insert_physio_file_parameter


def import_bids_meg_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    acquisition: MegAcquisition,
    bids_info: BidsAcquisitionInfo,
):
    # TODO: The file is actually a directory, it should be tared before proceeding to the hash.
    modality, output_type, file_type = group_errors_tuple(
        f"Error while checking database information for MEG acquisition '{bids_info.name}'.",
        lambda: get_check_bids_physio_modality(env, bids_info.data_type),
        lambda: get_check_bids_physio_output_type(env, args.type or 'raw'),
        lambda: get_check_bids_imaging_file_type(env, 'ctf'),
        # lambda: get_check_bids_physio_file_hash(env, acquisition),
    )

    # The files to copy to LORIS, with the source path on the left and the LORIS path on the right.
    files_to_copy: list[tuple[Path, Path]] = []

    loris_file_path = get_loris_bids_file_path(import_env, session, bids_info.data_type, acquisition.ctf_path)
    files_to_copy.append((acquisition.ctf_path, loris_file_path))

    loris_file = try_get_physio_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        import_env.ignored_files_count += 1
        return

    check_bids_meg_metadata_files(env, acquisition, bids_info)

    physio_file = insert_physio_file(
        env,
        session,
        loris_file_path,
        file_type,
        modality,
        output_type,
        bids_info.scan_row.get_acquisition_time() if bids_info.scan_row is not None else None
    )

    # insert_physio_file_parameter(env, physio_file, 'physiological_json_file_blake2b_hash', file_hash)
    for name, value in acquisition.sidecar.data.items():
        insert_physio_file_parameter(env, physio_file, name, value)

    if acquisition.events is not None:
        insert_bids_events_file(env, import_env, physio_file, session, bids_info, acquisition.events)
        loris_events_file_path = get_loris_bids_file_path(
            import_env, session, bids_info.data_type, acquisition.events.path
        )
        files_to_copy.append((acquisition.events.path, loris_events_file_path))
        if acquisition.events.dictionary is not None:
            insert_events_metadata_file(env, FileSource(physio_file), acquisition.events.dictionary)
            loris_events_dictionary_file_path = get_loris_bids_file_path(
                import_env, session, bids_info.data_type, acquisition.events.dictionary.path
            )
            files_to_copy.append((acquisition.events.dictionary.path, loris_events_dictionary_file_path))

    if acquisition.channels is not None:
        insert_bids_channels_file(env, import_env, physio_file, session, bids_info, acquisition.channels)
        loris_channels_file_path = get_loris_bids_file_path(
            import_env, session, bids_info.data_type, acquisition.channels.path
        )
        files_to_copy.append((acquisition.channels.path, loris_channels_file_path))

    for source_path, destination_path in files_to_copy:
        copy_loris_bids_file(import_env, source_path, destination_path)

    env.db.commit()

    log(env, f"MEG file succesfully imported with ID: {physio_file.id}.")

    # TODO: Remove the false.
    if get_eeg_viz_enabled_config(env):
        log(env, "Creating visualization chunks...")
        create_physio_channels_chunks(env, physio_file, acquisition.ctf_path)

    read_meg_channels(env, import_env, physio_file, acquisition, bids_info)

    env.db.commit()

    import_env.imported_files_count += 1


def check_bids_meg_metadata_files(env: Env, acquisition: MegAcquisition, bids_info: BidsAcquisitionInfo):
    """
    Check for the presence of BIDS metadata files for the BIDS MEG acquisition and warn the user if
    that is not the case.
    """

    if acquisition.channels is None:
        log_warning(env, f"No channels file found for acquisition '{bids_info.name}'.")

    if acquisition.events is None:
        log_warning(env, f"No events file found for acquisition '{bids_info.name}'.")

    if acquisition.events is not None and acquisition.events.dictionary is not None:
        log_warning(env, f"No events dictionary file found for acquisition '{bids_info.name}'.")
