
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_scanner import DbMriScanner


def try_get_scanner_with_info(
    db: Database,
    manufacturer: str,
    software_version: str,
    serial_number: str,
    model: str,
) -> DbMriScanner | None:
    """
    Get an MRI scanner from the database using the provided information, or return `None` if no
    scanner is found.
    """

    return db.execute(select(DbMriScanner)
        .where(DbMriScanner.manufacturer     == manufacturer)
        .where(DbMriScanner.model            == model)
        .where(DbMriScanner.serial_number    == serial_number)
        .where(DbMriScanner.software_version == software_version)
    ).scalar_one_or_none()
