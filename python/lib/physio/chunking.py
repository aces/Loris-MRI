
import subprocess
from pathlib import Path

from lib.config import get_data_dir_path_config, get_eeg_chunks_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.db.queries.physio_parameter import try_get_physio_file_parameter_with_file_id_name
from lib.env import Env
from lib.logging import log, log_error_exit
from lib.physio.file_parameters import insert_physio_file_parameter
from lib.util.path import get_path_stem


def get_dataset_chunks_dir_path(env: Env, physio_file: DbPhysioFile):
    """
    Get the chunks directory path of the dataset of a physiological file, creating that directory
    if it does not exist.
    """

    # The first part of the physiological file path is assumed to be the BIDS imports directory name.
    # The second part of the physiological file path is assumed to be the dataset name.
    eeg_chunks_dir_path = get_eeg_chunks_dir_path_config(env)
    if eeg_chunks_dir_path is None:
        data_dir = get_data_dir_path_config(env)
        eeg_chunks_dir_path = data_dir / physio_file.path.parts[0]

    eeg_chunks_path = eeg_chunks_dir_path / f'{physio_file.path.parts[1]}_chunks'
    eeg_chunks_path.mkdir(exist_ok=True)
    return eeg_chunks_path


def create_meg_signal_chunks(env: Env, physio_file: DbPhysioFile, ctf_path: Path):
    """
    Create the signal chunks for a physiological file based on its source MEG CTF directory.
    """

    data_dir = get_data_dir_path_config(env)

    # check if chunks already exists for this PhysiologicalFileID
    chunk_path = try_get_physio_file_parameter_with_file_id_name(
        env.db,
        physio_file.id,
        'electrophysiology_chunked_dataset_path',
    )

    if chunk_path is not None:
        log(env, "Chunk path already exists for this file.")
        return

    chunk_root_dir = get_dataset_chunks_dir_path(env, physio_file)

    command = ' '.join([
        'ctf-to-chunks',
        str(ctf_path),
        '--destination', str(chunk_root_dir),
        '--channel-count', str(10),
    ])

    try:
        log(env, f"Running chunking script with command: {command}")
        subprocess.call(
            command,
            shell = True,
        )
    except subprocess.CalledProcessError as error:
        log_error_exit(env, f"Chunking script execution failure. Error was:\n{error}")
    except OSError:
        log_error_exit(env, "Chunking script not found.")

    chunk_path = chunk_root_dir / f'{get_path_stem(physio_file.path)}.chunks'
    if not chunk_path.is_dir():
        log_error_exit(
            env,
            f"Chunk creation failed, directory '{chunk_path}' does not exist."
        )

    print(f"chunk path: {chunk_path}")
    print(f"data dir path: {data_dir}")
    print(f"relative chunk path: {chunk_path.relative_to(data_dir)}")

    insert_physio_file_parameter(
        env,
        physio_file,
        'electrophysiology_chunked_dataset_path',
        str(chunk_path.relative_to(data_dir)),
    )

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
