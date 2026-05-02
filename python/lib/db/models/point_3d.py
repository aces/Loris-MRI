from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPoint3D(Base):
    __tablename__ = 'point_3d'

    id : Mapped[int]   = mapped_column('Point3DID', primary_key=True)
    x  : Mapped[float] = mapped_column('X')
    y  : Mapped[float] = mapped_column('Y')
    z  : Mapped[float] = mapped_column('Z')
