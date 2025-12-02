from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioCoordSystemName(Base):
    __tablename__ = 'physiological_coord_system_name'

    id          : Mapped[int]        = mapped_column('PhysiologicalCoordSystemNameID', primary_key=True)
    name        : Mapped[str]        = mapped_column('Name')
    orientation : Mapped[str | None] = mapped_column('Orientation')
    origin      : Mapped[str | None] = mapped_column('Origin')
