from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbMriScanner(Base):
    __tablename__ = 'mri_scanner'

    id               : Mapped[int]           = mapped_column('ID', primary_key=True)
    manufacturer     : Mapped[Optional[str]] = mapped_column('Manufacturer')
    model            : Mapped[Optional[str]] = mapped_column('Model')
    serial_number    : Mapped[Optional[str]] = mapped_column('Serial_number')
    software_version : Mapped[Optional[str]] = mapped_column('Software')
    cand_id          : Mapped[Optional[int]] = mapped_column('CandID')
