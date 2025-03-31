from typing import Literal

from lib.db.queries.config import get_config_with_setting_name
from lib.env import Env
from lib.logging import log_error_exit


def get_patient_id_dicom_header_config(env: Env) -> Literal['PatientID', 'PatientName']:
    """
    Get the DICOM header in which to look for the patient ID from the database configuration.
    """

    config_value = get_config_with_setting_name(env.db, 'lookupCenterNameUsing').value
    match config_value:
        case 'PatientID':
            return 'PatientID'
        case 'PatientName':
            return 'PatientName'
        case _:
            log_error_exit(
                env,
                (
                    "Unexpected 'lookupCenterNameUsing' configuration setting, expected 'PatientID' or 'PatientName'"
                    f" but found '{config_value}'."
                )
            )
