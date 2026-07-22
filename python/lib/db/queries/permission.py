from collections.abc import Collection, Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.permission import DbPermission


def get_permissions_by_codes(db: Database, codes: Collection[str]) -> Sequence[DbPermission]:
    """Get the registered permissions having one of the supplied codes."""

    return db.execute(
        select(DbPermission).where(DbPermission.code.in_(codes))
    ).scalars().all()
