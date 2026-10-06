from pathlib import Path

from lib.db.models.physio_electrode import DbPhysioElectrode
from lib.db.models.physio_electrode_material import DbPhysioElectrodeMaterial
from lib.db.models.physio_electrode_type import DbPhysioElectrodeType
from lib.db.queries.physio_electrode import (
    try_get_electrode_material_with_name,
    try_get_electrode_type_with_name,
)
from lib.env import Env
from lib.physio.points import get_or_create_point


def get_or_create_electrode_type(env: Env, name: str) -> DbPhysioElectrodeType:
    """
    Get an electrode type by name or create it if it does not already exist.
    """

    electrode_type = try_get_electrode_type_with_name(env.db, name)
    if electrode_type is None:
        electrode_type = DbPhysioElectrodeType(name=name)
        env.db.add(electrode_type)
        env.db.flush()
    return electrode_type


def get_or_create_electrode_material(env: Env, name: str) -> DbPhysioElectrodeMaterial:
    """
    Get an electrode material by name or create it if it does not already exist.
    """

    material = try_get_electrode_material_with_name(env.db, name)
    if material is None:
        material = DbPhysioElectrodeMaterial(name=name)
        env.db.add(material)
        env.db.flush()
    return material


def insert_physio_electrode(
    env: Env,
    file_path: Path,
    name: str,
    x: float | None,
    y: float | None,
    z: float | None,
    electrode_type: DbPhysioElectrodeType | None,
    material: DbPhysioElectrodeMaterial | None,
    impedance: int | None,
    flush: bool = True,
) -> DbPhysioElectrode:
    """
    Insert a physiological electrode and its three-dimensional point.
    """

    point = get_or_create_point(env, x, y, z)
    electrode = DbPhysioElectrode(
        type_id     = electrode_type.id if electrode_type is not None else None,
        material_id = material.id if material is not None else None,
        name        = name,
        point_3d_id = point.id,
        impedance   = impedance,
        file_path   = file_path,
    )
    env.db.add(electrode)
    if flush:
        env.db.flush()
    return electrode
