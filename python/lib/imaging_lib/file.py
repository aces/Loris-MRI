import getpass
from datetime import datetime

from lib.db.models.file import DbFile
from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.session import DbSession
from lib.env import Env


def register_imaging_file(
    env: Env,
    file_type: str,
    file_rel_path: str,
    session: DbSession,
    mri_scan_type: DbMriScanType | None,
    echo_time: float | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
) -> DbFile:
    """
    Register an imaging file in the database.
    """

    user = getpass.getuser()
    time = datetime.now()

    file = DbFile(
        file_type                = file_type,
        rel_path                 = file_rel_path,
        session_id               = session.id,
        inserted_by_user_id      = user,
        insert_time              = time,
        coordinate_space         = 'native',
        output_type              = 'native',
        echo_time                = echo_time,
        echo_number              = echo_number,
        phase_encoding_direction = phase_encoding_direction,
        source_file_id           = None,
        scan_type_id             = mri_scan_type.id if mri_scan_type is not None else None,
    )

    env.db.add(file)
    env.db.commit()

    return file
