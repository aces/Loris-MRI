from datetime import datetime

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbUserLoginHistory(Base):
    __tablename__ = 'user_login_history'

    id              : Mapped[int]           = mapped_column('loginhistoryID', primary_key=True)
    username        : Mapped[str]           = mapped_column('userID', default='')
    success         : Mapped[bool]          = mapped_column('Success', YNBool, default=True)
    fail_code       : Mapped[str | None]    = mapped_column('Failcode')
    fail_detail     : Mapped[str | None]    = mapped_column('Fail_detail')
    login_timestamp : Mapped[datetime]      = mapped_column('Login_timestamp', default=datetime.now)
    ip_address      : Mapped[str | None]    = mapped_column('IP_address')
    page_requested  : Mapped[str | None]    = mapped_column('Page_requested')
