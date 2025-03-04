
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbProject(Base):
    __tablename__ = 'Project'

    id                  : Mapped[int]        = mapped_column('ProjectID', primary_key=True)
    name                : Mapped[str]        = mapped_column('Name')
    alias               : Mapped[str]        = mapped_column('Alias')
    recruitement_target : Mapped[int | None] = mapped_column('recruitmentTarget')
