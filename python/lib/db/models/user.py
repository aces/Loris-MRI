from datetime import date

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool
from lib.db.decorators.y_n_bool import YNBool


class DbUser(Base):
    __tablename__ = 'users'

    id                       : Mapped[int]          = mapped_column('ID', primary_key=True)
    user_id                  : Mapped[str]          = mapped_column('UserID')
    password                 : Mapped[str | None]   = mapped_column('Password')
    real_name                : Mapped[str | None]   = mapped_column('Real_name')
    first_name               : Mapped[str | None]   = mapped_column('First_name')
    last_name                : Mapped[str | None]   = mapped_column('Last_name')
    degree                   : Mapped[str | None]   = mapped_column('Degree')
    position_title           : Mapped[str | None]   = mapped_column('Position_title')
    institution              : Mapped[str | None]   = mapped_column('Institution')
    department               : Mapped[str | None]   = mapped_column('Department')
    address                  : Mapped[str | None]   = mapped_column('Address')
    city                     : Mapped[str | None]   = mapped_column('City')
    state                    : Mapped[str | None]   = mapped_column('State')
    zip_code                 : Mapped[str | None]   = mapped_column('Zip_code')
    country                  : Mapped[str | None]   = mapped_column('Country')
    phone                    : Mapped[str | None]   = mapped_column('Phone')
    fax                      : Mapped[str | None]   = mapped_column('Fax')
    email                    : Mapped[str]          = mapped_column('Email')
    privilege                : Mapped[bool]         = mapped_column('Privilege', IntBool)
    pscpi                    : Mapped[bool]         = mapped_column('PSCPI', YNBool)
    db_access                : Mapped[str]          = mapped_column('DBAccess')
    active                   : Mapped[bool]         = mapped_column('Active', YNBool)
    password_hash            : Mapped[str | None]   = mapped_column('Password_hash')
    password_change_required : Mapped[bool]         = mapped_column('PasswordChangeRequired', IntBool)
    totp_secret              : Mapped[bytes | None] = mapped_column('TOTPSecret')
    pending_approval         : Mapped[bool | None]  = mapped_column('Pending_approval', YNBool)
    doc_repo_notifications   : Mapped[bool | None]  = mapped_column('Doc_Repo_Notifications', YNBool)
    language_preference      : Mapped[int | None]   = mapped_column('language_preference')
    active_from              : Mapped[date | None]  = mapped_column('active_from')
    active_to                : Mapped[date | None]  = mapped_column('active_to')
    account_request_date     : Mapped[date | None]  = mapped_column('account_request_date')
