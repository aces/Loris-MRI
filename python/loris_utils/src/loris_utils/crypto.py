import hashlib
from hashlib import blake2b
from pathlib import Path


def compute_file_blake2b_hash(file_path: Path) -> str:
    """
    Compute the BLAKE2b hash of a file.
    """

    hash = blake2b()
    update_file_blake2b_hash(Path(file_path), hash)
    return hash.hexdigest()


def compute_directory_blake2b_hash(dir_path: Path) -> str:
    """
    Compute the BLAKE2b hash of a directory.
    """

    hash = blake2b()
    update_directory_blake2b_hash(dir_path, hash)
    return hash.hexdigest()


def update_file_blake2b_hash(file_path: Path, hash: blake2b):
    """
    Update a BLAKE2b hash with the contents of a file.
    """

    # Since the file given to this function may be large, we read it in chunks to avoid running
    # out of memory.
    with open(file_path, 'rb') as file:
        while chunk := file.read(1048576):
            hash.update(chunk)


def update_directory_blake2b_hash(dir_path: Path, hash: blake2b):
    """
    Update a BLAKE2b hash with the contents of a directory.
    """

    # The paths are sorted to ensure the hash is deterministic regardless of iteration order.
    for path in sorted(dir_path.iterdir()):
        # The file name is included in the hash to ensure the directory structure is reflected in
        # the hash.
        hash.update(path.name.encode())
        # Symlinks are currently not included in the hash.
        if path.is_file():
            update_file_blake2b_hash(path, hash)
        elif path.is_dir():
            update_directory_blake2b_hash(path, hash)


def compute_file_md5_hash(file_path: Path | str) -> str:
    """
    Compute the MD5 hash of a file.
    """

    # Since the file given to this function may be large, we read it in chunks to avoid running
    # out of memory.
    hash = hashlib.md5()
    with open(file_path, 'rb') as file:
        while chunk := file.read(1048576):
            hash.update(chunk)
    return hash.hexdigest()
