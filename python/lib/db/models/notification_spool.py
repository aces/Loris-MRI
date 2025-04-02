from datetime import datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.notification_type as db_notification_type
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbNotificationSpool(Base):
    __tablename__ = 'notification_spool'

    id           : Mapped[int]             = mapped_column('NotificationID', primary_key=True)
    type_id      : Mapped[int] \
        = mapped_column('NotificationTypeID', ForeignKey('notification_types.NotificationTypeID'))
    process_id   : Mapped[int | None]      = mapped_column('ProcessID')
    time_spooled : Mapped[datetime | None] = mapped_column('TimeSpooled')
    message      : Mapped[str | None]      = mapped_column('Message')
    error        : Mapped[bool | None]     = mapped_column('Error', YNBool)
    verbose      : Mapped[bool]            = mapped_column('Verbose', YNBool)
    sent         : Mapped[bool]            = mapped_column('Sent', YNBool)
    site_id      : Mapped[int | None]      = mapped_column('CenterID')
    origin       : Mapped[str | None]      = mapped_column('Origin')
    active       : Mapped[bool]            = mapped_column('Active', YNBool)

    type : Mapped['db_notification_type.DbNotificationType'] = relationship('DbNotificationType')
