from collections.abc import Collection

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.permission import DbPermission


def get_existing_permission_codes(db: Database, codes: Collection[str]) -> set[str]:
    """
    Get the registered permission codes from a collection of codes.
    """

    return set(db.execute(select(DbPermission.code)
        .where(DbPermission.code.in_(codes))
    ).scalars())
