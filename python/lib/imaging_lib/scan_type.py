from lib.db.models.mri_scan_type import DbMriScanType
from lib.env import Env


def create_mri_scan_type(env: Env, name: str) -> DbMriScanType:
    """
    Create an MRI scan type in the database.
    """

    scan_type = DbMriScanType(
        name = name,
    )

    env.db.add(scan_type)
    env.db.flush()

    return scan_type
