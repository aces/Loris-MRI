
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
