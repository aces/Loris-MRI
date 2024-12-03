from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioElectrodeMaterial(Base):
    __tablename__ = 'physiological_electrode_material'

    id   : Mapped[int] = mapped_column('PhysiologicalElectrodeMaterialID', primary_key=True)
    name : Mapped[str] = mapped_column('ElectrodeMaterial')
