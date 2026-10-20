from lib.db.models.bids_file import DbBidsFile
from lib.db.models.physio_coord_system import DbPhysioCoordSystem
from lib.db.models.physio_coord_system_electrode import DbPhysioCoordSystemElectrode
from lib.db.models.physio_coord_system_name import DbPhysioCoordSystemName
from lib.db.models.physio_coord_system_point_3d import DbPhysioCoordSystemPoint3d
from lib.db.models.physio_coord_system_type import DbPhysioCoordSystemType
from lib.db.models.physio_coord_system_unit import DbPhysioCoordSystemUnit
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.point_3d import DbPoint3D
from lib.db.queries.physio import try_get_physio_modality_with_name
from lib.db.queries.physio_coord_system import (
    try_get_coord_system,
    try_get_coord_system_electrode_relation,
    try_get_coord_system_name_with_name,
    try_get_coord_system_point_relation,
    try_get_coord_system_type_with_name,
    try_get_coord_system_unit_with_name,
    try_get_coord_system_unit_with_symbol,
    try_get_point_with_coordinates,
)
from lib.env import Env


def get_or_create_coord_system(
    env: Env,
    bids_file: DbBidsFile | None,
    modality: DbPhysioModality,
    coord_type: DbPhysioCoordSystemType,
    coord_name: DbPhysioCoordSystemName,
    coord_unit: DbPhysioCoordSystemUnit,
) -> DbPhysioCoordSystem:
    """
    Get a matching coordinate system or create it if it does not already exist.
    """

    coord_system = try_get_coord_system(
        env.db,
        bids_file.id if bids_file is not None else None,
        modality.id,
        coord_type.id,
        coord_name.id,
        coord_unit.id,
    )

    if coord_system is not None:
        return coord_system

    coord_system = DbPhysioCoordSystem(
        name_id      = coord_name.id,
        type_id      = coord_type.id,
        unit_id      = coord_unit.id,
        modality_id  = modality.id,
        file_path    = bids_file.dataset.path / bids_file.path if bids_file is not None else None,
        bids_file_id = bids_file.id if bids_file is not None else None,
    )

    env.db.add(coord_system)
    env.db.flush()
    return coord_system


def get_coord_system_type(env: Env, name: str) -> DbPhysioCoordSystemType:
    """
    Get a coordinate system type by name, falling back to `'Not registered'`.
    """

    coord_type = try_get_coord_system_type_with_name(env.db, name)
    if coord_type is None and name != 'Not registered':
        return get_coord_system_type(env, 'Not registered')

    if coord_type is None:
        raise ValueError("Missing 'Not registered' physiological coordinate system type")

    return coord_type


def get_coord_system_name(env: Env, name: str) -> DbPhysioCoordSystemName:
    """
    Get a coordinate system name, falling back to `'Not registered'`.
    """

    coord_name = try_get_coord_system_name_with_name(env.db, name)
    if coord_name is None and name != 'Not registered':
        return get_coord_system_name(env, 'Not registered')

    if coord_name is None:
        raise ValueError("Missing 'Not registered' physiological coordinate system name")

    return coord_name


def get_coord_system_unit(env: Env, symbol: str | None) -> DbPhysioCoordSystemUnit:
    """
    Get a coordinate system unit by symbol, falling back to `'Not registered'`.
    """

    if symbol is not None:
        coord_unit = try_get_coord_system_unit_with_symbol(env.db, symbol)
        if coord_unit is not None:
            return coord_unit

    coord_unit = try_get_coord_system_unit_with_name(env.db, 'Not registered')
    if coord_unit is None:
        raise ValueError("Missing 'Not registered' physiological coordinate system unit")

    return coord_unit


def get_or_create_point(env: Env, x: float, y: float, z: float) -> DbPoint3D:
    """
    Get a point with matching coordinates or create it if it does not already exist.
    """

    point = try_get_point_with_coordinates(env.db, x, y, z)
    if point is not None:
        return point

    point = DbPoint3D(x=x, y=y, z=z)
    env.db.add(point)
    env.db.flush()
    return point


def get_or_create_point_relation(
    env: Env,
    coord_system: DbPhysioCoordSystem,
    point: DbPoint3D,
    name: str,
) -> DbPhysioCoordSystemPoint3d:
    """
    Get a coordinate system point relation or create it if it does not already exist.
    """

    relation = try_get_coord_system_point_relation(env.db, coord_system.id, point.id)
    if relation is None:
        relation = DbPhysioCoordSystemPoint3d(
            coord_system_id = coord_system.id,
            point_3d_id     = point.id,
            name            = name,
        )
        env.db.add(relation)

    return relation


def get_or_create_electrode_relation(
    env: Env,
    coord_system: DbPhysioCoordSystem,
    electrode_id: int,
    physio_file: DbPhysioFile,
) -> DbPhysioCoordSystemElectrode:
    """
    Get a coordinate system electrode relation or create it if it does not already exist.
    """

    relation = try_get_coord_system_electrode_relation(env.db, coord_system.id, electrode_id)
    if relation is None:
        relation = DbPhysioCoordSystemElectrode(
            coord_system_id = coord_system.id,
            electrode_id    = electrode_id,
            physio_file_id  = physio_file.id,
        )
        env.db.add(relation)

    return relation


def get_physio_modality(env: Env, name: str) -> DbPhysioModality:
    """
    Get a physiological modality by name, falling back to `'Not registered'`.
    """

    modality = try_get_physio_modality_with_name(env.db, name)
    if modality is None and name != 'Not registered':
        return get_physio_modality(env, 'Not registered')
    if modality is None:
        raise ValueError("Missing 'Not registered' physiological modality")
    return modality
