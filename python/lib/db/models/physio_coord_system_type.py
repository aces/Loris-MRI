from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioCoordSystemType(Base):
    __tablename__ = 'physiological_coord_system_type'

    id   : Mapped[int] = mapped_column('PhysiologicalCoordSystemTypeID', primary_key=True)
    name : Mapped[str] = mapped_column('Name')
