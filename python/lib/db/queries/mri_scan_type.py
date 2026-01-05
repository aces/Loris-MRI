from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_scan_type import DbMriScanType


def try_get_mri_scan_type_with_id(db: Database, id: int) -> DbMriScanType | None:
    """
    Get an MRI scan type from the database using its ID, or return `None` if no scan type is found.
    """

    return db.execute(select(DbMriScanType)
        .where(DbMriScanType.id == id)
    ).scalar_one_or_none()


def try_get_mri_scan_type_with_name(db: Database, name: str) -> DbMriScanType | None:
    """
    Get an MRI scan type from the database using its name, or return `None` if no scan type is
    found.
    """

    return db.execute(select(DbMriScanType)
        .where(DbMriScanType.name == name)
    ).scalar_one_or_none()
