from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.hed_schema_node import DbHedSchemaNode


def get_all_hed_schema_nodes(db: Database) -> Sequence[DbHedSchemaNode]:
    """
    Get all the HED schema nodes from the database.
    """

    return db.execute(select(DbHedSchemaNode)).scalars().all()
