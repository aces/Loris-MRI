from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbConfigSetting(Base):
    __tablename__ = 'ConfigSettings'

    id             : Mapped[int]            = mapped_column('ID', primary_key=True, autoincrement=True, init=False)
    name           : Mapped[str]            = mapped_column('Name')
    description    : Mapped[Optional[str]]  = mapped_column('Description',   default=None)
    visible        : Mapped[Optional[bool]] = mapped_column('Visible',       default=False)
    allow_multiple : Mapped[Optional[bool]] = mapped_column('AllowMultiple', default=False)
    data_type      : Mapped[Optional[str]]  = mapped_column('DataType',      default=None)
    parent_id      : Mapped[Optional[int]]  = mapped_column('Parent',        default=None)
    label          : Mapped[Optional[str]]  = mapped_column('Label',         default=None)
    order_number   : Mapped[Optional[int]]  = mapped_column('OrderNumber',   default=None)
