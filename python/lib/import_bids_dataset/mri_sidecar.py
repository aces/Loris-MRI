from typing import Any

from loris_bids_reader.mri.sidecar import BidsMriSidecarJsonFile

from lib.config import get_patient_id_dicom_header_config
from lib.env import Env
from lib.get_session_info import SessionInfo, get_session_info
from lib.imaging_lib.file_parameter import map_bids_to_loris_file_parameters
from lib.imaging_lib.mri_scanner import MriScannerInfo


def get_bids_mri_sidecar_scanner_info(sidecar: BidsMriSidecarJsonFile) -> MriScannerInfo:
    """
    Get the scanner information of a BIDS MRI sidecar JSON file.
    """

    return MriScannerInfo(
        manufacturer     = sidecar.data.get('Manufaturer'),
        model            = sidecar.data.get('ManufacturersModelName'),
        serial_number    = sidecar.data.get('DeviceSerialNumber'),
        software_version = sidecar.data.get('SoftwareVersions'),
    )


def get_bids_mri_sidecar_session_info(env: Env, sidecar: BidsMriSidecarJsonFile) -> SessionInfo:
    """
    Get the session information for a BIDS MRI sidecar JSON file using the session identification
    configuration function, or raise a `SessionConfigError` if the configuration returned is
    incorrect.
    """

    patient_id_dicom_header = get_patient_id_dicom_header_config(env)
    match patient_id_dicom_header:
        case 'PatientID':
            patient_id = sidecar.data['PatientID']
        case 'PatientName':
            patient_id = sidecar.data['PatientName']

    scanner_info = get_bids_mri_sidecar_scanner_info(sidecar)

    return get_session_info(env, patient_id, scanner_info)


def add_bids_mri_sidecar_file_parameters(env: Env, sidecar: BidsMriSidecarJsonFile, file_parameters: dict[str, Any]):
    """
    Read a BIDS MRI sidecar JSON file and add its parameters to the LORIS file parameters
    dictionary.
    """

    sidecar_parameters = sidecar.data.copy()
    map_bids_to_loris_file_parameters(env, sidecar_parameters)
    file_parameters.update(sidecar_parameters)
