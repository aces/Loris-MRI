from lib.db.models.mri_scan_type import DbMriScanType
from lib.env import Env


def create_mri_scan_type(env: Env, name: str) -> DbMriScanType:
    """
    Create an MRI scan type in the database.
    """

    mri_scan_type = DbMriScanType(
        name = name,
    )

    env.db.add(mri_scan_type)
    env.db.commit()

    return mri_scan_type
