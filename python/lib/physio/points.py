from lib.db.models.point_3d import DbPoint3D
from lib.db.queries.physio_coord_system import try_get_point_with_coordinates
from lib.env import Env


def get_or_create_point(env: Env, x: float | None, y: float | None, z: float | None) -> DbPoint3D:
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
