from lib.config import get_eeg_viz_enabled_config
from lib.db.models.session import DbSession
from lib.db.queries.imaging_file_type import try_get_imaging_file_type_with_type
from lib.db.queries.physio import (
    try_get_physio_file_with_path,
    try_get_physio_modality_with_name,
    try_get_physio_output_type_with_name,
)
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
from lib.util.path import add_path_extension
from loris_bids_reader.meg.data_type import BIDSMEGAcquisition
from loris_bids_reader.scans import BIDSScanRow


def import_bids_meg_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    acquisition: BIDSMEGAcquisition,
    scan_row: BIDSScanRow | None,
):
    log(env, f"Found MEG acquisition '{acquisition.path}'.")
    log(env, f"Sidecar:\n{acquisition.sidecar.path}")
    if acquisition.channels is not None:
        log(env, f"Channels:\n{acquisition.channels.path}")
    if acquisition.events is not None:
        log(env, f"Events:\n{acquisition.events.path}")

    modality = try_get_physio_modality_with_name(env.db, acquisition.data_type.name)
    if modality is None:
        raise Exception('TODO: Modality not found')

    output_type = try_get_physio_output_type_with_name(env.db, args.type or 'raw')  # TODO: Make this pretty
    if output_type is None:
        raise Exception('TODO: Output type not found')

    file_type = try_get_imaging_file_type_with_type(env.db, 'ctf')
    if file_type is None:
        raise Exception('TODO: File type not found')

    loris_file_path = add_path_extension(
        get_loris_file_path(import_env, session, acquisition, acquisition.ctf_path),
        'tar.gz',
    )

    loris_file = try_get_physio_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        import_env.ignored_files_count += 1
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        return

    physio_file = insert_physio_file(
        env,
        session,
        modality,
        output_type,
        loris_file_path,
        file_type.type,
        scan_row.get_acquisition_time() if scan_row is not None else None
    )

    for name, value in acquisition.sidecar.data.model_dump(by_alias=True).items():
        insert_physio_file_parameter(env, physio_file, name, value)

    if acquisition.events is not None:
        insert_bids_events_file(env, import_env, physio_file, session, acquisition, acquisition.events)
        if import_env.loris_bids_path is not None:
            copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.events.path)
        if acquisition.events.dictionary is not None:
            insert_events_metadata_file(env, FileSource(physio_file), acquisition.events.dictionary)
            if import_env.loris_bids_path is not None:
                copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.events.dictionary.path)
        else:
            log_warning(env, f"No events dictionary file found for acquisition '{acquisition.name}'.")
    else:
        log_warning(env, f"No events file found for acquisition '{acquisition.name}'.")

    if acquisition.channels is not None:
        insert_bids_channels_file(env, import_env, physio_file, session, acquisition, acquisition.channels)
        if import_env.loris_bids_path is not None:
            copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.channels.path)

    if import_env.loris_bids_path is not None:
        archive_bids_directory(import_env.loris_bids_path, session, acquisition, acquisition.ctf_path)

    env.db.commit()

    print(f"FILE INSERTED WITH ID {physio_file.id}")

    if get_eeg_viz_enabled_config(env):
        print("CREATE EEG visualization chunks")
        create_meg_signal_chunks(env, physio_file, acquisition.ctf_path)

    env.db.commit()

    import_env.imported_files_count += 1
