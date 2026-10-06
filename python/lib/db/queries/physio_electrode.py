from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.physio_coord_system_electrode import DbPhysioCoordSystemElectrode
from lib.db.models.physio_electrode import DbPhysioElectrode
from lib.db.models.physio_electrode_material import DbPhysioElectrodeMaterial
from lib.db.models.physio_electrode_type import DbPhysioElectrodeType


def get_physio_electrodes_with_file_id(db: Database, physio_file_id: int) -> Sequence[DbPhysioElectrode]:
    """
    Get the electrodes associated with a physiological file.
    """

    return db.execute(
        select(DbPhysioElectrode)
        .join(
            DbPhysioCoordSystemElectrode,
            DbPhysioCoordSystemElectrode.electrode_id == DbPhysioElectrode.id,
        )
        .where(DbPhysioCoordSystemElectrode.physio_file_id == physio_file_id)
        .distinct()
    ).scalars().all()


def try_get_electrode_type_with_name(db: Database, name: str) -> DbPhysioElectrodeType | None:
    """
    Get an electrode type using its name, or return `None` if no electrode type was found.
    """

    return db.execute(select(DbPhysioElectrodeType)
        .where(DbPhysioElectrodeType.name == name)
    ).scalar_one_or_none()


def try_get_electrode_material_with_name(db: Database, name: str) -> DbPhysioElectrodeMaterial | None:
    """
    Get an electrode material using its name, or return `None` if no electrode material was found.
    """

    return db.execute(select(DbPhysioElectrodeMaterial)
        .where(DbPhysioElectrodeMaterial.name == name)
    ).scalar_one_or_none()
