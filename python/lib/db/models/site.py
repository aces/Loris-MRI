
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbSite(Base):
    __tablename__ = 'psc'

    id         : Mapped[int]         = mapped_column('CenterID', primary_key=True)
    name       : Mapped[str]         = mapped_column('Name')
    area       : Mapped[str | None]  = mapped_column('PSCArea')
    address    : Mapped[str | None]  = mapped_column('Address')
    city       : Mapped[str | None]  = mapped_column('City')
    state_id   : Mapped[int | None]  = mapped_column('StateID')
    zip        : Mapped[str | None]  = mapped_column('ZIP')
    phone_1    : Mapped[str | None]  = mapped_column('Phone1')
    phone_2    : Mapped[str | None]  = mapped_column('Phone2')
    contact_1  : Mapped[str | None]  = mapped_column('Contact1')
    contact_2  : Mapped[str | None]  = mapped_column('Contact2')
    alias      : Mapped[str]         = mapped_column('Alias')
    mri_alias  : Mapped[str]         = mapped_column('MRI_alias')
    account    : Mapped[str | None]  = mapped_column('Account')
    study_site : Mapped[bool | None] = mapped_column('Study_site', YNBool)
