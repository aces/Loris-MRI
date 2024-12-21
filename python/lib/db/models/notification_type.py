from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbNotificationType(Base):
    __tablename__ = 'notification_types'

    id         : Mapped[int]            = mapped_column('NotificationTypeID', primary_key=True)
    name       : Mapped[str]            = mapped_column('Type')
    private    : Mapped[Optional[bool]] = mapped_column('private')
    description: Mapped[Optional[str]]  = mapped_column('Description')
