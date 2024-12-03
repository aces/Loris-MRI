from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile


def try_get_meegqc_file_with_path(db: Database, path: Path) -> DbMeegqcFile | None:
    """
    Get a MEEGqc file from the database using its path, or return `None` if no MEEGqc file was
    found.
    """

    return db.execute(select(DbMeegqcFile)
        .where(DbMeegqcFile.path == path)
    ).scalar_one_or_none()
