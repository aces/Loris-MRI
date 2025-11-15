from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_coord_system_name as db_physio_coord_system_name
import lib.db.models.physio_coord_system_type as db_physio_coord_system_type
import lib.db.models.physio_coord_system_unit as db_physio_coord_system_unit
import lib.db.models.physio_modality as db_physio_modality
from lib.db.base import Base


class DbPhysioCoordSystem(Base):
    __tablename__ = 'physiological_coord_system'

    id          : Mapped[int]        = mapped_column('PhysiologicalCoordSystemID', primary_key=True)
    name_id     : Mapped[int]        = mapped_column('NameID', ForeignKey('physiological_coord_system_name.PhysiologicalCoordSystemNameID'))
    type_id     : Mapped[int]        = mapped_column('TypeID', ForeignKey('physiological_coord_system_type.PhysiologicalCoordSystemTypeID'))
    unit_id     : Mapped[int]        = mapped_column('UnitID', ForeignKey('physiological_coord_system_unit.PhysiologicalCoordSystemUnitID'))
    modality_id : Mapped[int]        = mapped_column('ModalityID', ForeignKey('physiological_modality.PhysiologicalModalityID'))
    file_path   : Mapped[str | None] = mapped_column('FilePath')

    name     : Mapped['db_physio_coord_system_name.DbPhysioCoordSystemName'] = relationship('DbPhysioCoordSystemName')
    type     : Mapped['db_physio_coord_system_type.DbPhysioCoordSystemType'] = relationship('DbPhysioCoordSystemType')
    unit     : Mapped['db_physio_coord_system_unit.DbPhysioCoordSystemUnit'] = relationship('DbPhysioCoordSystemUnit')
    modality : Mapped['db_physio_modality.DbPhysioModality']                 = relationship('DbPhysioModality')
