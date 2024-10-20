from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbNotificationType(Base):
    __tablename__ = 'notification_types'

    id         : Mapped[int]            = mapped_column('NotificationTypeID',
        primary_key=True, autoincrement=True, init=False)
    description: Mapped[Optional[str]]  = mapped_column('Description')
    name       : Mapped[str]            = mapped_column('Type',    default='')
    private    : Mapped[Optional[bool]] = mapped_column('private', default=False)
