from datetime import datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_coord_system as db_physio_coord_system
import lib.db.models.physio_electrode as db_physio_electrode
import lib.db.models.physio_file as db_physio_file
from lib.db.base import Base


class DbPhysioCoordSystemElectrode(Base):
    __tablename__ = 'physiological_coord_system_electrode_rel'

    coord_system_id: Mapped[int] = mapped_column(
        'PhysiologicalCoordSystemID',
        ForeignKey('physiological_coord_system.PhysiologicalCoordSystemID'),
        primary_key=True,
    )

    electrode_id: Mapped[int] = mapped_column(
        'PhysiologicalElectrodeID',
        ForeignKey('physiological_electrode.PhysiologicalElectrodeID'),
        primary_key=True,
    )

    physio_file_id: Mapped[int] = mapped_column(
        'PhysiologicalFileID',
        ForeignKey('physiological_file.PhysiologicalFileID', ondelete='CASCADE'),
    )

    insert_time     : Mapped[datetime] = mapped_column('InsertTime', default=datetime.now)

    coord_system : Mapped['db_physio_coord_system.DbPhysioCoordSystem'] = relationship('DbPhysioCoordSystem')
    electrode    : Mapped['db_physio_electrode.DbPhysioElectrode']      = relationship('DbPhysioElectrode')
    physio_file  : Mapped['db_physio_file.DbPhysioFile']                = relationship('DbPhysioFile')
