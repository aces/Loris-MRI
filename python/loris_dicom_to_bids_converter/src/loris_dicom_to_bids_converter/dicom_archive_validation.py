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


def validate_dicom_archive(env: Env, dicom_archive_path: Path, upload_id: int):
    """
    Validate a DICOM archive and update its MRI upload record.
    """

    mri_upload = try_get_mri_upload_with_id(env.db, upload_id)
    if mri_upload is None:
        log_error_exit(
            env,
            f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}",
            lib.exitcode.SELECT_FAILURE,
        )

    dicom_archive = mri_upload.dicom_archive
    if dicom_archive is None:
        log_error_exit(
            env,
            f"Did not find a DICOM archive associated with upload ID {mri_upload.id}",
            lib.exitcode.SELECT_FAILURE,
        )

    dicom_archive_dir_path = get_dicom_archive_dir_path_config(env)
    expected_dicom_archive_path = dicom_archive_dir_path / dicom_archive.path
    if expected_dicom_archive_path.resolve() != dicom_archive_path.resolve():
        log_error_exit(
            env,
            f"UploadID {upload_id} and ArchiveLocation {dicom_archive_path} do not refer to the same upload",
            lib.exitcode.SELECT_FAILURE,
        )

    mri_upload.inserting = True
    env.db.commit()
    env.add_cleanup(lambda: end_upload(env, mri_upload))
    env.init_notifier(mri_upload.id)

    validate_dicom_archive_session_info(env, dicom_archive, mri_upload)

    validate_dicom_archive_md5_hash(env, dicom_archive, mri_upload)

    log_verbose(env, f"DICOM archive {dicom_archive_path} is valid!")

    mri_upload.is_dicom_archive_validated = True
    mri_upload.inserting = False
    env.db.commit()


def validate_dicom_archive_session_info(env: Env, dicom_archive: DbDicomArchive, mri_upload: DbMriUpload):
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


def validate_dicom_archive_md5_hash(env: Env, dicom_archive: DbDicomArchive, mri_upload: DbMriUpload):
    """
    Validate a DICOM archive MD5 hash. If the hash is not valid, register the error in the MRI
    upload and exit with an error.
    """

    log_verbose(env, "Verifying DICOM archive MD5 hash")

    dicom_archive_path = get_dicom_archive_dir_path_config(env) / dicom_archive.path

    file_md5_hash = compute_file_md5_hash(dicom_archive_path)
    database_md5_hash = dicom_archive.md5_hash_archive.split()[0]

    log_verbose(
        env,
        f"hash for target: {file_md5_hash}; hash from database: {database_md5_hash}",
    )
    log_verbose(env, "Verifying DICOM archive MD5 hash")

    file_md5_hash = compute_file_md5_hash(dicom_archive_path)
    database_md5_hash = dicom_archive.md5_hash_archive.split()[0]

    log_verbose(
        env,
        f"hash for target: {file_md5_hash}; hash from database: {database_md5_hash}",
    )

    if file_md5_hash != database_md5_hash:
        mri_upload.is_dicom_archive_validated = False
        mri_upload.is_candidate_info_validated = False
        env.db.commit()

        log_error_exit(
            env,
            "ERROR: DICOM archive seems corrupted or modified. Upload will exit now.",
            lib.exitcode.CORRUPTED_FILE,
        )

    if file_md5_hash != database_md5_hash:
        mri_upload.is_dicom_archive_validated = False
        mri_upload.is_candidate_info_validated = False
        env.db.commit()

        log_error_exit(
            env,
            "ERROR: DICOM archive seems corrupted or modified. Upload will exit now.",
            lib.exitcode.CORRUPTED_FILE,
        )


def end_upload(env: Env, mri_upload: DbMriUpload):
    """
    Clear an MRI upload's running flag during error cleanup.
    """

    mri_upload.inserting = False
    env.db.commit()
