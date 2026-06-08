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


def get_meegqc_files_with_acquisition_file_id(db: Database, acquisition_file_id: int) -> list[DbMeegqcFile]:
    """
    Get the MEEGqc files associated with an acquisition file using its ID.
    """

    return list(db.execute(select(DbMeegqcFile)
        .where(DbMeegqcFile.acquisition_file_id == acquisition_file_id)
        .order_by(DbMeegqcFile.category, DbMeegqcFile.path)
    ).scalars())


def get_meegqc_files_with_acquisition_file_id_kind(
    db: Database,
    acquisition_file_id: int,
    kind: str,
) -> list[DbMeegqcFile]:
    """
    Get the MEEGqc files of a given kind associated with an acquisition file using its ID.
    """

    return list(db.execute(select(DbMeegqcFile)
        .where(
            DbMeegqcFile.acquisition_file_id == acquisition_file_id,
            DbMeegqcFile.category == kind,
        )
        .order_by(DbMeegqcFile.category, DbMeegqcFile.path)
    ).scalars())


def try_get_meegqc_file_with_id_acquisition_file_id(
    db: Database,
    meegqc_file_id: int,
    acquisition_file_id: int,
) -> DbMeegqcFile | None:
    """
    Get a MEEGqc file using its ID and acquisition file ID, or return `None` if no file was found.
    """

    return db.execute(select(DbMeegqcFile)
        .where(
            DbMeegqcFile.id == meegqc_file_id,
            DbMeegqcFile.acquisition_file_id == acquisition_file_id,
        )
    ).scalar_one_or_none()
