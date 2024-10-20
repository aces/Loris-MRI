from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbSite(Base):
    __tablename__ = 'psc'

    id         : Mapped[int]            = mapped_column('CenterID',
        primary_key=True, autoincrement=True, init=False)
    name       : Mapped[str]            = mapped_column('Name',               default='')
    area       : Mapped[Optional[str]]  = mapped_column('PSCArea',            default=None)
    address    : Mapped[Optional[str]]  = mapped_column('Address',            default=None)
    city       : Mapped[Optional[str]]  = mapped_column('City',               default=None)
    state_id   : Mapped[Optional[int]]  = mapped_column('StateID',            default=None)
    zip        : Mapped[Optional[str]]  = mapped_column('ZIP',                default=None)
    phone_1    : Mapped[Optional[str]]  = mapped_column('Phone1',             default=None)
    phone_2    : Mapped[Optional[str]]  = mapped_column('Phone2',             default=None)
    contact_1  : Mapped[Optional[str]]  = mapped_column('Contact1',           default=None)
    contact_2  : Mapped[Optional[str]]  = mapped_column('Contact2',           default=None)
    alias      : Mapped[str]            = mapped_column('Alias',              default='')
    mri_alias  : Mapped[str]            = mapped_column('MRI_alias',          default='')
    account    : Mapped[Optional[str]]  = mapped_column('Account',            default=None)
    study_site : Mapped[Optional[bool]] = mapped_column('Study_site', YNBool, default=False)
