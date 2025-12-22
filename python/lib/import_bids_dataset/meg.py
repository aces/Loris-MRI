from pathlib import Path

from lib.config import get_eeg_viz_enabled_config
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.session import DbSession
from lib.db.queries.imaging_file_type import try_get_imaging_file_type_with_type
from lib.db.queries.physio import (
    try_get_physio_file_with_path,
    try_get_physio_modality_with_name,
    try_get_physio_output_type_with_name,
)
from lib.db.queries.physio_parameter import try_get_physio_file_parameter_with_file_id_name
from lib.env import Env
from lib.imaging_lib.physio import insert_physio_file, insert_physio_file_parameter
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.copy_files import copy_bids_file, get_loris_file_path
from lib.import_bids_dataset.env import BIDSImportEnv
from lib.logging import log
from loris_bids_reader.meg.data_type import BIDSMEGAcquisition
from loris_bids_reader.scans import BIDSScanRow


def import_bids_meg_acquisition(
    env: Env,
    import_env: BIDSImportEnv,
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

    loris_file_path = get_loris_file_path(import_env, session, acquisition, acquisition.ctf_path)

    loris_file = try_get_physio_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        import_env.ignored_files_count += 1
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        return

    file = insert_physio_file(
        env,
        session,
        modality,
        output_type,
        loris_file_path,
        file_type.type,
        scan_row.get_acquisition_time() if scan_row is not None else None
    )

    for name, value in acquisition.sidecar.data.model_dump(by_alias=True).items():
        insert_physio_file_parameter(env, file, session, name, value)

    if import_env.loris_bids_path is not None:
        copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.ctf_path)

    env.db.commit()

    print(f"FILE INSERTED WITH ID {file.id}")

    if get_eeg_viz_enabled_config(env):
        print("CREATE EEG visualization chunks")


# TODO: Make this prettier and likelize factorize somewhere else.
def create_chunks_for_visualization(env: Env, physio_file: DbPhysioFile, data_dir: Path):
    """
    Calls chunking scripts if no chunk datasets yet available for
    PhysiologicalFileID based on the file type of the original
    electrophysiology dataset.

    :param physio_file_id: PhysiologicalFileID of the dataset to chunk
        :type physio_file_id: int
    :param data_dir      : LORIS data directory (/data/%PROJECT%/data)
        :type data_dir      : str
    """

    # check if chunks already exists for this PhysiologicalFileID
    chunk_path = try_get_physio_file_parameter_with_file_id_name(
        env.db,
        physio_file.id,
        'electrophysiology_chunked_dataset_path',
    )

    if chunk_path is not None:
        return

    """
    # No chunks found
    script    = None
    file_path = self.grep_file_path_from_file_id(physio_file_id)

    chunk_root_dir_config = self.config_db_obj.get_config("EEGChunksPath")
    chunk_root_dir = chunk_root_dir_config
    file_path_parts = Path(file_path).parts
    if chunk_root_dir_config:
        chunk_root_dir = chunk_root_dir_config
    else:
        chunk_root_dir = os.path.join(data_dir, file_path_parts[0])

    chunk_root_dir = os.path.join(chunk_root_dir, f'{file_path_parts[1]}_chunks')

    full_file_path = os.path.join(data_dir, file_path)

    # determine which script to run based on the file type
    file_type = self.grep_file_type_from_file_id(physio_file_id)
    match file_type:
        case 'set':
            script = 'eeglab-to-chunks'
        case 'edf':
            script = 'edf-to-chunks'

    command = script + ' ' + full_file_path + ' --destination ' + chunk_root_dir

    # chunk the electrophysiology dataset if a command was determined above
    try:
        subprocess.call(
            command,
            shell = True,
            stdout = open(os.devnull, 'wb')
        )
    except subprocess.CalledProcessError as err:
        print(f'ERROR: {script} execution failure. Error was:\n {err}')
        sys.exit(lib.exitcode.CHUNK_CREATION_FAILURE)
    except OSError:
        print('ERROR: ' + script + ' not found')
        sys.exit(lib.exitcode.CHUNK_CREATION_FAILURE)

    chunk_path = os.path.join(chunk_root_dir, os.path.splitext(os.path.basename(file_path))[0] + '.chunks')
    if os.path.isdir(chunk_path):
        self.insert_physio_parameter_file(
            physiological_file_id = physio_file_id,
            parameter_name = 'electrophysiology_chunked_dataset_path',
            value = os.path.relpath(chunk_path, data_dir)
        )
    """
