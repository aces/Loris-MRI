from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.mri_protocol_group import DbMriProtocolGroup


def try_get_mri_protocol_group_with_id(db: Database, id: int) -> DbMriProtocolGroup | None:
    """
    Get an MRI protocol group from the database using its ID, or return `None` if no protocol
    group is found.
    """

    return db.execute(select(DbMriProtocolGroup)
        .where(DbMriProtocolGroup.id == id)
    ).scalar_one_or_none()
