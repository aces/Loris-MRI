from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_coord_system as db_physio_coord_system
import lib.db.models.point_3d as db_point_3d
from lib.db.base import Base


class DbPhysioCoordSystemPoint3d(Base):
    __tablename__ = 'physiological_coord_system_point_3d_rel'

    coord_system_id : Mapped[int]        = mapped_column(
        'PhysiologicalCoordSystemID',
        ForeignKey('physiological_coord_system.PhysiologicalCoordSystemID'),
        primary_key=True,
    )

    point_3d_id: Mapped[int] = mapped_column(
        'Point3DID',
        ForeignKey('point_3d.Point3DID'),
        primary_key=True,
    )

    name            : Mapped[str | None] = mapped_column('Name')

    coord_system : Mapped['db_physio_coord_system.DbPhysioCoordSystem'] = relationship('DbPhysioCoordSystem')
    point        : Mapped['db_point_3d.DbPoint3D']                      = relationship('DbPoint3D')
