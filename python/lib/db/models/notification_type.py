from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbNotificationType(Base):
    __tablename__ = 'notification_types'

    id         : Mapped[int]         = mapped_column('NotificationTypeID', primary_key=True)
    name       : Mapped[str]         = mapped_column('Type')
    private    : Mapped[bool | None] = mapped_column('private')
    description: Mapped[str | None]  = mapped_column('Description')
