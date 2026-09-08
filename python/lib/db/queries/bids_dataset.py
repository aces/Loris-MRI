from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.bids_dataset import DbBidsDataset


def try_get_bids_dataset_with_path(db: Database, path: Path) -> DbBidsDataset | None:
    """
    Get a BIDS dataset from the database using its path, or return `None` if no dataset is found.
    """

    return db.execute(select(DbBidsDataset)
        .where(DbBidsDataset.path == path)
    ).scalar_one_or_none()
