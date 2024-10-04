from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbConfigSetting(Base):
    __tablename__ = 'ConfigSettings'

    id             : Mapped[int]            = mapped_column('ID', primary_key=True)
    name           : Mapped[str]            = mapped_column('Name')
    description    : Mapped[Optional[str]]  = mapped_column('Description')
    visible        : Mapped[Optional[bool]] = mapped_column('Visible')
    allow_multiple : Mapped[Optional[bool]] = mapped_column('AllowMultiple')
    data_type      : Mapped[Optional[str]]  = mapped_column('DataType')
    parent_id      : Mapped[Optional[int]]  = mapped_column('Parent')
    label          : Mapped[Optional[str]]  = mapped_column('Label')
    order_number   : Mapped[Optional[int]]  = mapped_column('OrderNumber')
