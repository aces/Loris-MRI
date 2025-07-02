from typing import Any

from lib.config import get_patient_id_dicom_header_config
from lib.env import Env
from lib.get_session_info import SessionInfo, get_session_info
from lib.imaging_lib.mri_scanner import MriScannerInfo


def get_bids_json_scanner_info(bids_json: dict[str, Any]) -> MriScannerInfo:
    """
    Get the scanner information of a BIDS JSON sidecar file.
    """

    return MriScannerInfo(
        manufacturer     = bids_json.get('Manufaturer'),
        model            = bids_json.get('ManufacturersModelName'),
        serial_number    = bids_json.get('DeviceSerialNumber'),
        software_version = bids_json.get('SoftwareVersions'),
    )


def get_bids_json_session_info(env: Env, bids_json: dict[str, Any]) -> SessionInfo:
    """
    Get the session information for a BIDS JSON sidecar file using the session identification
    configuration function, or raise a `SessionConfigError` if the configuration returned is
    incorrect.
    """

    patient_id_dicom_header = get_patient_id_dicom_header_config(env)
    match patient_id_dicom_header:
        case 'PatientID':
            patient_id = bids_json['PatientID']
        case 'PatientName':
            patient_id = bids_json['PatientName']

    scanner_info = get_bids_json_scanner_info(bids_json)

    return get_session_info(env, patient_id, scanner_info)
