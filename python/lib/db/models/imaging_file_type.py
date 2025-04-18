from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbImagingFileType(Base):
    __tablename__ = 'ImagingFileTypes'

    type        : Mapped[str]        = mapped_column('type', primary_key=True)
    description : Mapped[str | None] = mapped_column('description')
