from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbConfigSetting(Base):
    __tablename__ = 'ConfigSettings'

    id             : Mapped[int]         = mapped_column('ID', primary_key=True)
    name           : Mapped[str]         = mapped_column('Name')
    description    : Mapped[str | None]  = mapped_column('Description')
    visible        : Mapped[bool | None] = mapped_column('Visible')
    allow_multiple : Mapped[bool | None] = mapped_column('AllowMultiple')
    data_type      : Mapped[str | None]  = mapped_column('DataType')
    parent_id      : Mapped[int | None]  = mapped_column('Parent')
    label          : Mapped[str | None]  = mapped_column('Label')
    order_number   : Mapped[int | None]  = mapped_column('OrderNumber')
