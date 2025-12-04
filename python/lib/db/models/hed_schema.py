from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbHedSchema(Base):
    __tablename__ = 'hed_schema'

    id          : Mapped[int]        = mapped_column('ID', primary_key=True)
    name        : Mapped[str]        = mapped_column('Name')
    version     : Mapped[str]        = mapped_column('Version')
    description : Mapped[str | None] = mapped_column('Description')
    url         : Mapped[str]        = mapped_column('URL')
