from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbVisit(Base):
    __tablename__  = 'visit'

    id    : Mapped[int] = mapped_column('VisitID', primary_key=True)
    name  : Mapped[str] = mapped_column('VisitName')
    label : Mapped[str] = mapped_column('VisitLabel')
