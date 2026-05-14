from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioCoordSystemPoint3d(Base):
    __tablename__ = 'physiological_coord_system_point_3d_rel'

    coord_system_id : Mapped[int]      = mapped_column('PhysiologicalCoordSystemID', primary_key=True)
    point_3d_id     : Mapped[int]      = mapped_column('Point3DID', primary_key=True)
    name            : Mapped[str]      = mapped_column('Name')
