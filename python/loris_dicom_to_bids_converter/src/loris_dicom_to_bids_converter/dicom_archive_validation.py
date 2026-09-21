from pathlib import Path

import lib.exitcode
from lib.config import get_dicom_archive_dir_path_config
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_upload import DbMriUpload
from lib.db.queries.mri_upload import try_get_mri_upload_with_id
from lib.env import Env
from lib.get_session_info import SessionConfigError, get_dicom_archive_session_info
from lib.logging import log_error_exit, log_verbose, log_warning
from loris_utils.crypto import compute_file_md5_hash


def validate_dicom_archive(env: Env, dicom_archive_path: Path, upload_id: int) -> None:
    """
    Validate a DICOM archive and update its MRI upload record.
    """

    mri_upload = get_mri_upload(env, upload_id)
    dicom_archive = get_dicom_archive(env, mri_upload)
    validate_archive_path(env, dicom_archive, dicom_archive_path, upload_id)

    mri_upload.inserting = True
    env.db.commit()
    env.add_cleanup(lambda: end_upload(env, mri_upload))
    env.init_notifier(mri_upload.id)

    validate_session_info(env, dicom_archive, mri_upload)
    validate_md5_sum(env, dicom_archive, mri_upload, dicom_archive_path)

    log_verbose(env, f"DICOM archive {dicom_archive_path} is valid!")

    mri_upload.is_dicom_archive_validated = True
    mri_upload.inserting = False
    env.db.commit()


def get_mri_upload(env: Env, upload_id: int) -> DbMriUpload:
    """
    Return an MRI upload with the provided ID, or exit if it does not exist.
    """

    mri_upload = try_get_mri_upload_with_id(env.db, upload_id)
    if mri_upload is None:
        log_error_exit(
            env,
            f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}",
            lib.exitcode.SELECT_FAILURE,
        )

    return mri_upload


def get_dicom_archive(env: Env, mri_upload: DbMriUpload) -> DbDicomArchive:
    """
    Return an MRI upload's DICOM archive, or exit if it has none.
    """

    dicom_archive = mri_upload.dicom_archive
    if dicom_archive is None:
        log_error_exit(
            env,
            f"Did not find a DICOM archive associated with upload ID {mri_upload.id}",
            lib.exitcode.SELECT_FAILURE,
        )

    return dicom_archive


def validate_archive_path(env: Env, dicom_archive: DbDicomArchive, dicom_archive_path: Path, upload_id: int):
    """Verify that the provided path identifies the upload's DICOM archive."""

    archive_relative_path = dicom_archive.path
    if archive_relative_path is None:
        log_error_exit(
            env,
            f"DICOM archive {dicom_archive.id} does not have an archive path",
            lib.exitcode.SELECT_FAILURE,
        )

    expected_path = get_dicom_archive_dir_path_config(env) / archive_relative_path
    if expected_path.resolve() != dicom_archive_path.resolve():
        log_error_exit(
            env,
            f"UploadID {upload_id} and ArchiveLocation {dicom_archive_path} do not refer to the same upload",
            lib.exitcode.SELECT_FAILURE,
        )


def validate_session_info(env: Env, dicom_archive: DbDicomArchive, mri_upload: DbMriUpload):
    """
    Validate the session information derived from the DICOM archive.
    """

    try:
        session_info = get_dicom_archive_session_info(env, dicom_archive)
        mri_upload.is_candidate_info_validated = True
        env.db.commit()

        log_verbose(
            env,
            f"Found Center Name: {session_info.session.site.name}, Center ID: {session_info.session.site.id}",
        )
        log_verbose(env, f"Found scanner ID: {session_info.scanner.id}")
    except SessionConfigError as error:
        log_warning(env, str(error))
        mri_upload.is_candidate_info_validated = False
        env.db.commit()


def validate_md5_sum(env: Env, dicom_archive: DbDicomArchive, mri_upload: DbMriUpload, dicom_archive_path: Path):
    """
    Validate a DICOM archive checksum registering the error in the MRI upload and exiting with an
    error if the checksum is not valid.
    """

    log_verbose(env, "Verifying DICOM archive md5sum (checksum)")

    if validate_dicom_archive_md5_sum(env, dicom_archive, dicom_archive_path):
        return

    mri_upload.is_dicom_archive_validated = False
    mri_upload.is_candidate_info_validated = False
    env.db.commit()

    log_error_exit(
        env,
        "ERROR: DICOM archive seems corrupted or modified. Upload will exit now.",
        lib.exitcode.CORRUPTED_FILE,
    )


def validate_dicom_archive_md5_sum(env: Env, dicom_archive: DbDicomArchive, dicom_archive_path: Path) -> bool:
    """
    Return whether a DICOM archive's file and database MD5 sums match.
    """

    file_md5_sum = compute_file_md5_hash(dicom_archive_path)
    database_full_md5_sum = dicom_archive.md5_sum_archive
    if database_full_md5_sum is None:
        log_verbose(env, "No DICOM archive checksum was found in the database")
        return False

    database_md5_sum = database_full_md5_sum.split()[0]

    log_verbose(
        env,
        f"checksum for target: {file_md5_sum}; checksum from database: {database_md5_sum}",
    )

    return file_md5_sum == database_md5_sum


def end_upload(env: Env, mri_upload: DbMriUpload):
    """
    Clear an MRI upload's running flag during error cleanup.
    """

    mri_upload.inserting = False
    env.db.commit()
