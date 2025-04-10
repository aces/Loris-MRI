from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.queries.mri_scan_type import try_get_mri_scan_type_with_name
from lib.env import Env


def get_or_create_scan_type(env: Env, name: str) -> DbMriScanType:
    """
    Get an MRI scan type from the database using its name, or create it if it does not already
    exist.
    """

    mri_scan_type = try_get_mri_scan_type_with_name(env.db, name)

    if mri_scan_type is not None:
        return mri_scan_type

    mri_scan_type = DbMriScanType(
        name = name,
    )

    env.db.add(mri_scan_type)
    env.db.commit()

    return mri_scan_type
