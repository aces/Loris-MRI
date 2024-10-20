from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbProject(Base):
    __tablename__ = 'Project'

    id                  : Mapped[int]           = mapped_column('ProjectID',
        primary_key=True, autoincrement=True, init=False)
    name                : Mapped[str]           = mapped_column('Name')
    alias               : Mapped[str]           = mapped_column('Alias')
    recruitement_target : Mapped[Optional[int]] = mapped_column('recruitmentTarget', default=None)
