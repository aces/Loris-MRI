from datetime import datetime

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioCoordSystemElectrode(Base):
    __tablename__ = 'physiological_coord_system_electrode_rel'

    coord_system_id : Mapped[int]      = mapped_column('PhysiologicalCoordSystemID', primary_key=True)
    electrode_id    : Mapped[int]      = mapped_column('PhysiologicalElectrodeID', primary_key=True)
    physio_file_id  : Mapped[int]      = mapped_column('PhysiologicalFileID')
    insert_time     : Mapped[datetime] = mapped_column('InsertTime', default=datetime.now)
