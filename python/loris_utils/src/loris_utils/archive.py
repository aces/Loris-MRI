import tarfile
from pathlib import Path


def create_archive_with_files(archive_path: Path, file_paths: list[Path]):
    """
    Create a tar archive with the provided files. Files are added to the archive using their base
    name, so the name of the provided files should all be distinct.
    """

    with tarfile.open(archive_path, 'w:gz') as tar:
        for file_path in file_paths:
            tar.add(file_path, arcname=file_path.name)
