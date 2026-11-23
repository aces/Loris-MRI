from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.bids_mri_scan_type import DbBidsMriScanType


def try_get_bids_mri_scan_type_with_scan_type_id(db: Database, scan_type_id: int) -> DbBidsMriScanType | None:
    """
    Get the BIDS naming information from the database using its MRI scan type ID, or return
    `None` if no mapping is found.
    """

    return db.execute(select(DbBidsMriScanType)
        .join(DbBidsMriScanType.category)
        .join(DbBidsMriScanType.bids_scan_type)
        .where(DbBidsMriScanType.scan_type_id == scan_type_id)
    ).scalar_one_or_none()
