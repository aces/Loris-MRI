import json
from pathlib import Path
from typing import Any

from lib.config import get_patient_id_dicom_header_config
from lib.env import Env
from lib.get_session_info import SessionInfo, get_session_info
from lib.imaging_lib.mri_scanner import MriScannerInfo
from lib.import_bids_dataset.imaging import map_bids_param_to_loris_param
from lib.util.crypto import compute_file_blake2b_hash


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


def add_bids_json_file_parameters(
    env: Env,
    bids_json_path: Path,
    loris_json_path: Path,
    file_parameters: dict[str, Any],
):
    """
    Read a BIDS JSON sidecar file and add its parameters to a LORIS file parameters dictionary.
    """

    with open(bids_json_path) as data_file:
        file_parameters.update(json.load(data_file))
        map_bids_param_to_loris_param(env, file_parameters)

    json_blake2 = compute_file_blake2b_hash(bids_json_path)

    file_parameters['bids_json_file']              = str(loris_json_path)
    file_parameters['bids_json_file_blake2b_hash'] = json_blake2
