from collections.abc import Sequence
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.bids_file import DbBidsFile


def get_bids_files_with_dataset_id(db: Database, dataset_id: int) -> Sequence[DbBidsFile]:
    """
    Get the BIDS files of a BIDS dataset from the database using its dataset ID.
    """

    return db.execute(select(DbBidsFile)
        .where(DbBidsFile.dataset_id == dataset_id)
    ).scalars().all()


def try_get_bids_file_with_dataset_id_path(db: Database, dataset_id: int, path: Path) -> DbBidsFile | None:
    """
    Get a BIDS file from the database using its dataset ID and path, or return `None` if no file is
    found.
    """

    return db.execute(select(DbBidsFile)
        .where(DbBidsFile.dataset_id == dataset_id)
        .where(DbBidsFile.path == path)
    ).scalar_one_or_none()
