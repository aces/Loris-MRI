from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioElectrodeType(Base):
    __tablename__ = 'physiological_electrode_type'

    id   : Mapped[int] = mapped_column('PhysiologicalElectrodeTypeID', primary_key=True)
    name : Mapped[str] = mapped_column('ElectrodeType')
