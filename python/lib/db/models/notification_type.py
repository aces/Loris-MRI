from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool


class DbNotificationType(Base):
    __tablename__ = 'notification_types'

    id         : Mapped[int]         = mapped_column('NotificationTypeID', primary_key=True)
    name       : Mapped[str]         = mapped_column('Type', default='')
    private    : Mapped[bool | None] = mapped_column('private', IntBool, default=False)
    description: Mapped[str | None]  = mapped_column('Description')
