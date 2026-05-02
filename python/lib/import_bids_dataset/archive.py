from pathlib import Path

from loris_utils.archive import create_archive_with_files
from loris_utils.crypto import compute_file_blake2b_hash
from loris_utils.path import remove_path_extension

from lib.config import get_data_dir_path_config, get_ephys_archive_dir_path_config
from lib.db.models.physio_event_archive import DbPhysioEventArchive
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_file_archive import DbPhysioFileArchive
from lib.env import Env


def import_physio_file_archive(env: Env, physio_file: DbPhysioFile, file_paths: list[Path]):
    """
    Create and import a physiological file archive into LORIS.
    """

    archive_rel_path = get_archive_path(env, physio_file.path)

    data_dir_path = get_data_dir_path_config(env)
    archive_path = data_dir_path / archive_rel_path
    if archive_path.exists():
        raise Exception(f"Archive '{archive_rel_path}' already exists on the file system.")

    archive_path.parent.mkdir(exist_ok=True)

    create_archive_with_files(archive_path, file_paths)

    blake2b_hash = compute_file_blake2b_hash(archive_path)

    env.db.add(DbPhysioFileArchive(
        physio_file_id = physio_file.id,
        path           = archive_rel_path,
        blake2b_hash   = blake2b_hash,
    ))

    env.db.flush()


def import_physio_event_archive(env: Env, physio_file: DbPhysioFile, file_paths: list[Path]):
    """
    Create and import a physiological event archive into LORIS. The name of the archive is based on
    the first file path provided.
    """

    data_dir_path = get_data_dir_path_config(env)
    archive_rel_path = remove_path_extension(file_paths[0].relative_to(data_dir_path)).with_suffix('.tgz')

    archive_path = data_dir_path / archive_rel_path
    if archive_path.exists():
        raise Exception(f"Event archive '{archive_rel_path}' already exists on the file system.")

    create_archive_with_files(archive_path, file_paths)

    blake2b_hash = compute_file_blake2b_hash(archive_path)

    env.db.add(DbPhysioEventArchive(
        physio_file_id = physio_file.id,
        path           = archive_rel_path,
        blake2b_hash   = blake2b_hash,
    ))

    env.db.flush()


def get_archive_path(env: Env, file_path: Path) -> Path:
    """
    Get the path of a physiological file archive relative to the LORIS data directory.
    """

    archive_rel_path = remove_path_extension(file_path).with_suffix('.tgz')
    archive_dir_path = get_ephys_archive_dir_path_config(env)
    if archive_dir_path is not None:
        data_dir_path = get_data_dir_path_config(env)
        return (archive_dir_path / 'raw' / archive_rel_path.name).relative_to(data_dir_path)
    else:
        return archive_rel_path
