from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbUserProject(Base):
    """
    Relationship between users and projects.
    """

    __tablename__ = 'user_project_rel'

    user_id    : Mapped[int] = mapped_column('UserID',    ForeignKey('users.ID'),          primary_key=True)
    project_id : Mapped[int] = mapped_column('ProjectID', ForeignKey('Project.ProjectID'), primary_key=True)
