from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioCoordSystemUnit(Base):
    __tablename__ = 'physiological_coord_system_unit'

    id     : Mapped[int]        = mapped_column('PhysiologicalCoordSystemUnitID', primary_key=True)
    name   : Mapped[str]        = mapped_column('Name')
    symbol : Mapped[str | None] = mapped_column('Symbol')
