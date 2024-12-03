from lib.db.models.bids_file import DbBidsFile
from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile, DbMeegqcFileAcquisition


def try_get_meegqc_file_with_bids_info_id(db: Database, bids_info_id: int) -> DbMeegqcFile | None:
    """
    Get an MEEGqc file using its BIDS file ID, or return `None` if no MEEGqc file was found.
    """

    return db.execute(select(DbMeegqcFile)
        .where(DbMeegqcFile.bids_info_id == bids_info_id)
    ).scalar_one_or_none()


def get_meegqc_files_with_acquisition_file_id(db: Database, acquisition_file_id: int) -> list[DbMeegqcFile]:
    """
    Get the MEEGqc files associated with an acquisition file using its ID.
    """

    return list(db.execute(select(DbMeegqcFile)
        .join(DbMeegqcFileAcquisition)
        .join(DbMeegqcFile.bids_info)
        .where(DbMeegqcFileAcquisition.acquisition_file_id == acquisition_file_id)
        .order_by(DbMeegqcFile.category, DbBidsFile.path)
    ).scalars())


def get_meegqc_files_with_acquisition_file_id_category(
    db: Database,
    acquisition_file_id: int,
    category: str,
) -> list[DbMeegqcFile]:
    """
    Get the MEEGqc files of a given category associated with an acquisition file using its ID.
    """

    return list(db.execute(select(DbMeegqcFile)
        .join(DbMeegqcFileAcquisition)
        .join(DbMeegqcFile.bids_info)
        .where(
            DbMeegqcFileAcquisition.acquisition_file_id == acquisition_file_id,
            DbMeegqcFile.category == category,
        )
        .order_by(DbMeegqcFile.category, DbBidsFile.path)
    ).scalars())


def try_get_meegqc_file_with_id_acquisition_file_id(
    db: Database,
    meegqc_file_id: int,
    acquisition_file_id: int,
) -> DbMeegqcFile | None:
    """
    Get an MEEGqc file using its ID and acquisition file ID, or return `None` if no file was found.
    """

    return db.execute(select(DbMeegqcFile)
        .join(DbMeegqcFileAcquisition)
        .where(
            DbMeegqcFile.id == meegqc_file_id,
            DbMeegqcFileAcquisition.acquisition_file_id == acquisition_file_id,
        )
    ).scalar_one_or_none()
