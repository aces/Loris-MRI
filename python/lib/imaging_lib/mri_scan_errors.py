from datetime import datetime
from pathlib import Path
from typing import Any

from loris_utils.iter import map_non_none

from lib.db.models.candidate import DbCandidate
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_protocol_group import DbMriProtocolGroup
from lib.db.models.mri_scan_classification_error import DbMriScanClassificationError
from lib.db.models.mri_scan_identification_error import DbMriScanIdentificationError
from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.mri_scan_validation_error import DbMriScanValidationError
from lib.db.models.session import DbSession
from lib.db.queries.mri_scan_classification_error import try_get_matching_mri_scan_classification_error
from lib.db.queries.mri_scan_identification_error import try_get_matching_mri_scan_identification_error
from lib.db.queries.mri_scan_validation_error import try_get_matching_mri_scan_validation_error
from lib.env import Env


def register_mri_scan_identification_error(
    env: Env,
    patient_name: str | None,
    dicom_archive: DbDicomArchive | None,
    file_path: Path,
    series_uid: str | None,
    echo_time: float | None,
    reason: str,
) -> DbMriScanIdentificationError:
    """
    Register an MRI scan identification error in the database using the provided information,
    or return the existing error if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None

    error = try_get_matching_mri_scan_identification_error(
        env.db, dicom_archive_id, series_uid, echo_time, patient_name, reason,
    )

    if error is not None:
        return error

    error = DbMriScanIdentificationError(
        time_run         = datetime.now(),
        dicom_archive_id = dicom_archive_id,
        file_path        = file_path,
        patient_name     = patient_name,
        reason           = reason,
        series_uid       = series_uid,
        echo_time        = echo_time,
    )

    env.db.add(error)
    env.db.flush()

    return error


def register_mri_scan_classification_error(
    env: Env,
    file_path: Path,
    candidate: DbCandidate,
    dicom_archive: DbDicomArchive | None,
    protocol_group: DbMriProtocolGroup | None,
    patient_name: str | None,
    scan_parameters: dict[str, Any],
) -> DbMriScanClassificationError:
    """
    Register an MRI scan classification error in the database using the provided information,
    or return the existing error if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None
    series_uid = scan_parameters.get('SeriesInstanceUID')
    echo_time = map_non_none(scan_parameters.get('EchoTime'), str)
    echo_number = map_non_none(scan_parameters.get('EchoNumber'), repr)
    phase_direction = scan_parameters.get('PhaseEncodingDirection')

    scan = try_get_matching_mri_scan_classification_error(
        env.db, dicom_archive_id, series_uid, echo_time, echo_number, phase_direction,
    )

    if scan is not None:
        return scan

    scan = DbMriScanClassificationError(
        candidate_id             = candidate.id,
        pscid                    = candidate.psc_id,
        dicom_archive_id         = dicom_archive_id,
        time_run                 = datetime.now(),
        patient_name             = patient_name,
        file_path                = file_path,
        protocol_group_id        = protocol_group.id if protocol_group is not None else None,
        series_uid               = series_uid,
        series_description       = scan_parameters.get('SeriesDescription'),
        image_type               = map_non_none(scan_parameters.get('ImageType'), str),
        tr_range                 = map_non_none(scan_parameters.get('RepetitionTime'), str),
        te_range                 = echo_time,
        ti_range                 = map_non_none(scan_parameters.get('InversionTime'), str),
        slice_thickness_range    = map_non_none(scan_parameters.get('SliceThickness'), str),
        xspace_range             = map_non_none(scan_parameters.get('xspace'), str),
        yspace_range             = map_non_none(scan_parameters.get('yspace'), str),
        zspace_range             = map_non_none(scan_parameters.get('zspace'), str),
        xstep_range              = map_non_none(scan_parameters.get('xstep'), str),
        ystep_range              = map_non_none(scan_parameters.get('ystep'), str),
        zstep_range              = map_non_none(scan_parameters.get('zstep'), str),
        time_range               = map_non_none(scan_parameters.get('time'), str),
        echo_number              = echo_number,
        phase_encoding_direction = phase_direction,
    )

    env.db.add(scan)
    env.db.flush()

    return scan


def register_mri_scan_validation_error(
    env: Env,
    session: DbSession,
    dicom_archive: DbDicomArchive | None,
    scan_type: DbMriScanType,
    file_path: Path,
    patient_name: str | None,
    series_uid: str | None,
    echo_time: float | None,
    echo_number: str | None,
    phase_encoding_direction: str | None,
    protocol_check_group_id: int | None,
    check_id: int | None,
    severity: str,
    header: str,
    value: str | None,
    valid_range: str | None,
    valid_regex: str | None,
) -> DbMriScanValidationError:
    """
    Register an MRI scan validation error in the database using the provided information,
    or return the existing error if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None

    violation = try_get_matching_mri_scan_validation_error(
        env.db, dicom_archive_id, series_uid, echo_time, echo_number, phase_encoding_direction,
        scan_type.id, severity, header, value, valid_range, valid_regex,
    )

    if violation is not None:
        return violation

    violation = DbMriScanValidationError(
        time_run                 = datetime.now(),
        dicom_archive_id         = dicom_archive_id,
        candidate_id             = session.candidate_id,
        visit_label              = session.visit_label,
        scan_type_id             = scan_type.id,
        file_path                = file_path,
        patient_name             = patient_name,
        series_uid               = series_uid,
        echo_time                = echo_time,
        echo_number              = echo_number,
        phase_encoding_direction = phase_encoding_direction,
        protocol_check_group_id  = protocol_check_group_id,
        check_id                 = check_id,
        severity                 = severity,
        header                   = header,
        value                    = value,
        valid_range              = valid_range,
        valid_regex              = valid_regex,
    )

    env.db.add(violation)
    env.db.flush()

    return violation
