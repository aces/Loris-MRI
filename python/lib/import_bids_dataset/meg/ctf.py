from pathlib import Path

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from loris_bids_reader.meg.reader import BidsMegDataTypeReader
from loris_utils.archive import create_archive_with_file
from loris_utils.error import group_errors_tuple
from loris_utils.path import add_path_extension

from lib.config import (
    get_data_dir_path_config,
    get_ephys_archive_dir_path_config,
    get_ephys_visualization_enabled_config,
)
from lib.db.models.meg_ctf_head_shape_file import DbMegCtfHeadShapeFile
from lib.db.models.session import DbSession
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.env import Env
from lib.import_bids_dataset.acquisitions import import_bids_acquisitions
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.channels import insert_bids_channels_file
from lib.import_bids_dataset.copy_files import copy_loris_bids_file, get_loris_bids_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import insert_bids_event_dict_file
from lib.import_bids_dataset.events_tsv import insert_bids_events_file
from lib.import_bids_dataset.file_type import get_check_bids_imaging_file_type
from lib.import_bids_dataset.meg.ctf_head_shape import insert_head_shape_file
from lib.import_bids_dataset.physio import (
    get_check_bids_physio_file_hash,
    get_check_bids_physio_modality,
    get_check_bids_physio_output_type,
)
from lib.logging import log, log_warning
from lib.physio.chunking import create_physio_channels_chunks
from lib.physio.events import EventDictFileSource
from lib.physio.file import insert_physio_file
from lib.physio.parameters import insert_physio_file_parameter


def import_bids_meg_data_type(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsMegDataTypeReader,
):
    if data_type.head_shape_file is not None:
        head_shape_file_path = get_loris_bids_file_path(
            import_env,
            session,
            data_type.name,
            data_type.head_shape_file.path,
        )

        head_shape_file = insert_head_shape_file(env, data_type.head_shape_file, head_shape_file_path)
        copy_loris_bids_file(import_env, data_type.head_shape_file.path, head_shape_file_path)
    else:
        head_shape_file = None

    import_bids_acquisitions(
        env,
        import_env,
        data_type.acquisitions,
        lambda acquisition, bids_info: import_bids_meg_acquisition(
            env,
            import_env,
            args,
            session,
            acquisition,
            bids_info,
            head_shape_file,
        ),
    )


def import_bids_meg_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    acquisition: MegAcquisition,
    bids_info: BidsAcquisitionInfo,
    head_shape_file: DbMegCtfHeadShapeFile | None,
):
    modality, output_type, file_type, file_hash = group_errors_tuple(
        f"Error while checking database information for MEG acquisition '{bids_info.name}'.",
        lambda: get_check_bids_physio_modality(env, bids_info.data_type),
        lambda: get_check_bids_physio_output_type(env, args.type or 'raw'),
        lambda: get_check_bids_imaging_file_type(env, 'ctf'),
        lambda: get_check_bids_physio_file_hash(env, acquisition.ctf_path),
    )

    # The files to copy to LORIS, with the source path on the left and the LORIS path on the right.
    files_to_copy: list[tuple[Path, Path]] = []

    loris_file_path = get_loris_bids_file_path(import_env, session, bids_info.data_type, acquisition.ctf_path)
    files_to_copy.append((acquisition.ctf_path, loris_file_path))

    loris_file = try_get_physio_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        import_env.ignored_acquisitions_count += 1
        return

    check_bids_meg_metadata_files(env, acquisition, bids_info)

    ctf_archive_path = get_ctf_archive_path(env, loris_file_path)
    create_archive_with_file(import_env.data_dir_path / ctf_archive_path, acquisition.ctf_path)

    physio_file = insert_physio_file(
        env,
        session,
        loris_file_path,
        file_type,
        modality,
        output_type,
        bids_info.scan_row.get_acquisition_time() if bids_info.scan_row is not None else None,
        ctf_archive_path,
        head_shape_file,
    )

    insert_physio_file_parameter(env, physio_file, 'physiological_file_blake2b_hash', file_hash)
    for name, value in acquisition.sidecar_file.data.items():
        insert_physio_file_parameter(env, physio_file, name, value)

    if acquisition.events_file is not None:
        insert_bids_events_file(env, import_env, physio_file, session, bids_info, acquisition.events_file)
        loris_events_file_path = get_loris_bids_file_path(
            import_env, session, bids_info.data_type, acquisition.events_file.path
        )
        files_to_copy.append((acquisition.events_file.path, loris_events_file_path))
        if acquisition.events_file.dictionary is not None:
            loris_event_dict_file_path = get_loris_bids_file_path(
                import_env, session, bids_info.data_type, acquisition.events_file.dictionary.path
            )

            insert_bids_event_dict_file(
                env,
                EventDictFileSource.from_file(physio_file),
                acquisition.events_file.dictionary,
                loris_event_dict_file_path,
            )

            files_to_copy.append((acquisition.events_file.dictionary.path, loris_event_dict_file_path))

    if acquisition.channels_file is not None:
        insert_bids_channels_file(env, import_env, physio_file, session, bids_info, acquisition.channels_file)
        loris_channels_file_path = get_loris_bids_file_path(
            import_env, session, bids_info.data_type, acquisition.channels_file.path
        )
        files_to_copy.append((acquisition.channels_file.path, loris_channels_file_path))

    for source_path, destination_path in files_to_copy:
        copy_loris_bids_file(import_env, source_path, destination_path)

    env.db.commit()

    log(env, f"MEG file succesfully imported with ID: {physio_file.id}.")

    if get_ephys_visualization_enabled_config(env):
        log(env, "Creating visualization chunks...")
        create_physio_channels_chunks(env, physio_file)

    env.db.commit()


def check_bids_meg_metadata_files(env: Env, acquisition: MegAcquisition, bids_info: BidsAcquisitionInfo):
    """
    Check for the presence of BIDS metadata files for the BIDS MEG acquisition and warn the user if
    that is not the case.
    """

    if acquisition.channels_file is None:
        log_warning(env, f"No channels file found for acquisition '{bids_info.name}'.")

    if acquisition.events_file is None:
        log_warning(env, f"No events file found for acquisition '{bids_info.name}'.")

    if acquisition.events_file is not None and acquisition.events_file.dictionary is not None:
        log_warning(env, f"No events dictionary file found for acquisition '{bids_info.name}'.")


def get_ctf_archive_path(env: Env, loris_ctf_path: Path) -> Path:
    """
    Get the path of a CTF archive.
    """

    archive_rel_path = add_path_extension(loris_ctf_path, 'tgz')
    archive_dir_path = get_ephys_archive_dir_path_config(env)
    if archive_dir_path is not None:
        data_dir_path = get_data_dir_path_config(env)
        archive_path = archive_dir_path / 'ctf' / archive_rel_path.name
        archive_path.parent.mkdir(exist_ok=True, parents=True)
        return (archive_path).relative_to(data_dir_path)
    else:
        return archive_rel_path
