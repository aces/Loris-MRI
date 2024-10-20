from datetime import datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.notification_type as db_notification_type
from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbNotificationSpool(Base):
    __tablename__ = 'notification_spool'

    id           : Mapped[int]                = mapped_column('NotificationID',
        primary_key=True, autoincrement=True, init=False)
    type_id      : Mapped[int]                = mapped_column('NotificationTypeID',
        ForeignKey('notification_types.NotificationTypeID'))
    process_id   : Mapped[int]                = mapped_column('ProcessID')
    message      : Mapped[Optional[str]]      = mapped_column('Message')
    time_spooled : Mapped[Optional[datetime]] = mapped_column('TimeSpooled',     default=None)
    error        : Mapped[Optional[bool]]     = mapped_column('Error', YNBool,   default=None)
    verbose      : Mapped[bool]               = mapped_column('Verbose', YNBool, default=False)
    sent         : Mapped[bool]               = mapped_column('Sent', YNBool,    default=False)
    site_id      : Mapped[Optional[int]]      = mapped_column('CenterID',        default=None)
    origin       : Mapped[Optional[str]]      = mapped_column('Origin',          default=None)
    active       : Mapped[bool]               = mapped_column('Active', YNBool,  default=True)

    type : Mapped['db_notification_type.DbNotificationType'] = relationship('DbNotificationType', init=False)
