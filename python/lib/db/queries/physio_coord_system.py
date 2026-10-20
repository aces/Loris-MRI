from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.physio_coord_system import DbPhysioCoordSystem
from lib.db.models.physio_coord_system_electrode import DbPhysioCoordSystemElectrode
from lib.db.models.physio_coord_system_name import DbPhysioCoordSystemName
from lib.db.models.physio_coord_system_point_3d import DbPhysioCoordSystemPoint3d
from lib.db.models.physio_coord_system_type import DbPhysioCoordSystemType
from lib.db.models.physio_coord_system_unit import DbPhysioCoordSystemUnit
from lib.db.models.point_3d import DbPoint3D


def try_get_coord_system_type_with_name(db: Database, name: str) -> DbPhysioCoordSystemType | None:
    """
    Get a coordinate system type using its name, or return `None` if no coordinate system was found.
    """

    return db.execute(select(DbPhysioCoordSystemType)
        .where(DbPhysioCoordSystemType.name == name)
    ).scalar_one_or_none()


def try_get_coord_system_name_with_name(db: Database, name: str) -> DbPhysioCoordSystemName | None:
    """
    Get a coordinate system name using its name, or return `None` if no coordinate system was found.
    """

    return db.execute(select(DbPhysioCoordSystemName)
        .where(DbPhysioCoordSystemName.name == name)
    ).scalar_one_or_none()


def try_get_coord_system_unit_with_symbol(db: Database, symbol: str) -> DbPhysioCoordSystemUnit | None:
    """
    Get a coordinate system unit using its symbol, or return `None` if no coordinate system was
    found.
    """

    return db.execute(select(DbPhysioCoordSystemUnit)
        .where(DbPhysioCoordSystemUnit.symbol == symbol)
    ).scalar_one_or_none()


def try_get_coord_system_unit_with_name(db: Database, name: str) -> DbPhysioCoordSystemUnit | None:
    """
    Get a coordinate system unit using its name, or return `None` if no coordinate system was found.
    """

    return db.execute(select(DbPhysioCoordSystemUnit)
        .where(DbPhysioCoordSystemUnit.name == name)
    ).scalar_one_or_none()


def try_get_coord_system(
    db: Database,
    bids_info_id: int | None,
    modality_id: int,
    type_id: int,
    name_id: int,
    unit_id: int,
) -> DbPhysioCoordSystem | None:
    """
    Get a coordinate system using its identifying fields, or return `None` if no coordinate system
    was found.
    """

    return db.execute(select(DbPhysioCoordSystem).where(
        DbPhysioCoordSystem.bids_file_id == bids_info_id,
        DbPhysioCoordSystem.modality_id == modality_id,
        DbPhysioCoordSystem.type_id == type_id,
        DbPhysioCoordSystem.name_id == name_id,
        DbPhysioCoordSystem.unit_id == unit_id,
    )).scalar_one_or_none()


def try_get_point_with_coordinates(db: Database, x: float | None, y: float | None, z: float | None) -> DbPoint3D | None:
    """
    Get a three-dimensional point using its coordinates, or return `None` if none was found.
    """

    return db.execute(select(DbPoint3D).where(
        DbPoint3D.x == x,
        DbPoint3D.y == y,
        DbPoint3D.z == z,
    )).scalar_one_or_none()


def try_get_coord_system_point_relation(
    db: Database,
    coord_system_id: int,
    point_id: int,
) -> DbPhysioCoordSystemPoint3d | None:
    """
    Get a coordinate system point relation using its IDs, or return `None` if none was found.
    """

    return db.execute(select(DbPhysioCoordSystemPoint3d).where(
        DbPhysioCoordSystemPoint3d.coord_system_id == coord_system_id,
        DbPhysioCoordSystemPoint3d.point_3d_id == point_id,
    )).scalar_one_or_none()


def try_get_coord_system_electrode_relation(
    db: Database,
    coord_system_id: int,
    electrode_id: int,
) -> DbPhysioCoordSystemElectrode | None:
    """
    Get a coordinate system electrode relation using its IDs, or return `None` if none was found.
    """

    return db.execute(select(DbPhysioCoordSystemElectrode).where(
        DbPhysioCoordSystemElectrode.coord_system_id == coord_system_id,
        DbPhysioCoordSystemElectrode.electrode_id == electrode_id,
    )).scalar_one_or_none()
