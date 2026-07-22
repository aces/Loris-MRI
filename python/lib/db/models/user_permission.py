from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbUserPermission(Base):
    """
    Relationship between users and permissions.
    """

    __tablename__ = 'user_perm_rel'

    user_id       : Mapped[int] = mapped_column('userID', ForeignKey('users.ID'), primary_key=True, default=0)
    permission_id : Mapped[int] = mapped_column('permID', ForeignKey('permissions.permID'), primary_key=True, default=0)
