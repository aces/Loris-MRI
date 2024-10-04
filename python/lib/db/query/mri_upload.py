from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.model.mri_upload import DbMriUpload


def try_get_mri_upload_with_id(db: Database, id: int):
    """
    Get an MRI upload from the database using its ID, or return `None` if no MRI upload is found.
    """

    return db.execute(select(DbMriUpload)
        .where(DbMriUpload.id == id)
    ).scalar_one_or_none()
