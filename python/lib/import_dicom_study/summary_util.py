from lib.config import get_patient_id_dicom_header_config
from lib.env import Env
from lib.get_session_info import SessionInfo, get_session_info
from lib.import_dicom_study.summary_type import DicomStudySummary
from lib.scanner import MriScannerInfo


def get_dicom_study_summary_scanner_info(dicom_summary: DicomStudySummary) -> MriScannerInfo:
    """
    Get a subject information using a DICOM study summary.
    """

    return MriScannerInfo(
        manufacturer     = dicom_summary.info.scanner.manufacturer,
        model            = dicom_summary.info.scanner.model,
        serial_number    = dicom_summary.info.scanner.serial_number,
        software_version = dicom_summary.info.scanner.software_version,
    )


def get_dicom_study_summary_session_info(env: Env, dicom_summary: DicomStudySummary) -> SessionInfo:
    """
    Get the session information for a DICOM study summary object using the session identification
    configuration function, or raise a `SessionConfigError` if the configuration returned is
    incorrect.
    """

    patient_id_dicom_header = get_patient_id_dicom_header_config(env)
    match patient_id_dicom_header:
        case 'PatientID':
            patient_id = dicom_summary.info.patient.id
        case 'PatientName':
            patient_id = dicom_summary.info.patient.name

    scanner_info = get_dicom_study_summary_scanner_info(dicom_summary)

    return get_session_info(env, patient_id, scanner_info)
