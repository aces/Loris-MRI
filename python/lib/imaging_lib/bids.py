import re
from typing import Any

from lib.config import get_patient_id_dicom_header_config
from lib.db.queries.imaging_file_type import get_all_imaging_file_types
from lib.env import Env
from lib.get_session_info import SessionInfo, get_session_info
from lib.scanner import MriScannerInfo


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


def determine_bids_file_type(env: Env, file_name: str) -> str | None:
    """
    Determine the file type of a BIDS file from the database using its name, or return `None` if no
    corresponding file type is found.
    """

    imaging_file_types = get_all_imaging_file_types(env.db)

    for imaging_file_type in imaging_file_types:
        regex = re.escape(imaging_file_type.type) + r'(\.gz)?$'
        if re.search(regex, file_name):
            return imaging_file_type.type

    return None
