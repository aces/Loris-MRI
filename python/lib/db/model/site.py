from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbSite(Base):
    __tablename__ = 'psc'

    id         : Mapped[int]            = mapped_column('CenterID', primary_key=True)
    name       : Mapped[str]            = mapped_column('Name')
    area       : Mapped[Optional[str]]  = mapped_column('PSCArea')
    address    : Mapped[Optional[str]]  = mapped_column('Address')
    city       : Mapped[Optional[str]]  = mapped_column('City')
    state_id   : Mapped[Optional[int]]  = mapped_column('StateID')
    zip        : Mapped[Optional[str]]  = mapped_column('ZIP')
    phone_1    : Mapped[Optional[str]]  = mapped_column('Phone1')
    phone_2    : Mapped[Optional[str]]  = mapped_column('Phone2')
    contact_1  : Mapped[Optional[str]]  = mapped_column('Contact1')
    contact_2  : Mapped[Optional[str]]  = mapped_column('Contact2')
    alias      : Mapped[str]            = mapped_column('Alias')
    mri_alias  : Mapped[str]            = mapped_column('MRI_alias')
    account    : Mapped[Optional[str]]  = mapped_column('Account')
    study_site : Mapped[Optional[bool]] = mapped_column('Study_site', YNBool)
