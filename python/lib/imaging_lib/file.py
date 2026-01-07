import getpass
from datetime import date, datetime
from pathlib import Path

from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.file import DbFile
from lib.db.models.mri_scanner import DbMriScanner
from lib.db.models.session import DbSession
from lib.env import Env


def register_mri_file(
    env: Env,
    file_type: str,
    file_path: Path,
    session: DbSession,
    scan_type_id: int | None,
    scanner: DbMriScanner | None,
    dicom_archive: DbDicomArchive | None,
    series_instance_uid: str | None,
    echo_time: float | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
    acquisition_date: date | None,
    caveat: bool,
) -> DbFile:
    """
    Register an MRI file in the database.
    """

    user = getpass.getuser()
    time = datetime.now()

    file = DbFile(
        file_type                = file_type,
        path                     = file_path,
        session_id               = session.id,
        inserted_by_user_id      = user,
        insert_time              = time,
        coordinate_space         = 'native',
        output_type              = 'native',
        series_uid               = series_instance_uid,
        echo_time                = echo_time,
        echo_number              = echo_number,
        phase_encoding_direction = phase_encoding_direction,
        source_file_id           = None,
        scan_type_id             = scan_type_id,
        scanner_id               = scanner.id if scanner is not None else None,
        dicom_archive_id         = dicom_archive.id if dicom_archive is not None else None,
        caveat                   = caveat,
        acquisition_date         = acquisition_date,
    )

    env.db.add(file)
    env.db.flush()

    return file
