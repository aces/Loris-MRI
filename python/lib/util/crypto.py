import hashlib
from pathlib import Path


def compute_file_blake2b_hash(file_path: Path | str) -> str:
    """
    Compute the BLAKE2b hash of a file.
    """

    # Since the file given to this function may be large, we read it in chunks to avoid running
    # out of memory.
    hash = hashlib.blake2b()
    with open(file_path, 'rb') as file:
        while chunk := file.read(1048576):
            hash.update(chunk)
    return hash.hexdigest()


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
