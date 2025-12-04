from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbHedSchemaNode(Base):
    __tablename__ = 'hed_schema_nodes'

    id          : Mapped[int]        = mapped_column('ID', primary_key=True)
    parent_id   : Mapped[int | None] = mapped_column('ParentID', ForeignKey('hed_schema_nodes.ID'))
    schema_id   : Mapped[int]        = mapped_column('SchemaID', ForeignKey('hed_schema.ID'))
    name        : Mapped[str]        = mapped_column('Name')
    long_name   : Mapped[str]        = mapped_column('LongName')
    description : Mapped[str]        = mapped_column('Description')
