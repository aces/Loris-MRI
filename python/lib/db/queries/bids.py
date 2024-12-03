from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.bids_file import DbBidsFile
from lib.db.models.physio_file import DbPhysioFile


def get_physio_files_with_bids_dataset_id(db: Database, bids_dataset_id: int) -> Sequence[DbPhysioFile]:
    """
    Get the physiological files associated with the files from a BIDS dataset using the BIDS dataset
    ID.
    """

    return db.execute(select(DbPhysioFile)
        .join(DbPhysioFile.bids_info)
        .where(DbBidsFile.dataset_id == bids_dataset_id)
    ).scalars().all()
