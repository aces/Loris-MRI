
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbMriScanner(Base):
    __tablename__ = 'mri_scanner'

    id               : Mapped[int]        = mapped_column('ID', primary_key=True)
    manufacturer     : Mapped[str | None] = mapped_column('Manufacturer')
    model            : Mapped[str | None] = mapped_column('Model')
    serial_number    : Mapped[str | None] = mapped_column('Serial_number')
    software_version : Mapped[str | None] = mapped_column('Software')
    candidate_id     : Mapped[int | None] = mapped_column('CandidateID')
