import os
from typing import Literal

from lib.db.queries.config import try_get_config_with_setting_name
from lib.env import Env
from lib.logging import log_error_exit


def get_patient_id_dicom_header_config(env: Env) -> Literal['PatientID', 'PatientName']:
    """
    Get the DICOM header in which to look for the patient ID from the in-database configuration, or
    exit the program with an error if that configuration value does not exist or is incorrect.
    """

    patient_id_dicom_header = _get_config_value(env, 'lookupCenterNameUsing')

    if patient_id_dicom_header not in ('PatientID', 'PatientName'):
        log_error_exit(
            env,
            (
                "Unexpected patient ID DICOM header configuration value, expected 'PatientID' or 'PatientName' but"
                f" found '{patient_id_dicom_header}'."
            )
        )

    return patient_id_dicom_header


def get_default_bids_visit_label_config(env: Env) -> str:
    """
    Get the default BIDS visit label from the in-database configuration, or exit the program with
    an error if that configuration value does not exist.
    """

    return _get_config_value(env, 'default_bids_vl')


def get_data_dir_path_config(env: Env) -> str:
    """
    Get the LORIS base data directory path from the in-database configuration, or exit the program
    with an error if that configuration value does not exist or is incorrect.
    """

    data_dir_path = os.path.normpath(_get_config_value(env, 'dataDirBasepath'))

    if not os.path.isdir(data_dir_path):
        log_error_exit(
            env,
            (
                f"The LORIS base data directory path configuration value '{data_dir_path}' does not refer to an"
                " existing directory."
            )
        )

    if not os.access(data_dir_path, os.R_OK) or not os.access(data_dir_path, os.W_OK):
        log_error_exit(
            env,
            f"Missing read or write permission on the LORIS base data directory '{data_dir_path}'.",
        )

    return data_dir_path


def get_dicom_archive_dir_path_config(env: Env) -> str:
    """
    Get the LORIS DICOM archive directory path from the in-database configuration, or exit the
    program with an error if that configuration value does not exist or is incorrect.
    """

    dicom_archive_dir_path = os.path.normpath(_get_config_value(env, 'tarchiveLibraryDir'))

    if not os.path.isdir(dicom_archive_dir_path):
        log_error_exit(
            env,
            (
                f"The LORIS DICOM archive directory path configuration value '{dicom_archive_dir_path}' does not refer"
                " to an existing diretory."
            ),
        )

    if not os.access(dicom_archive_dir_path, os.R_OK) or not os.access(dicom_archive_dir_path, os.W_OK):
        log_error_exit(
            env,
            f"Missing read or write permission on the LORIS DICOM archive directory '{dicom_archive_dir_path}'.",
        )

    return dicom_archive_dir_path


def _get_config_value(env: Env, setting_name: str) -> str:
    """
    Get a configuration value from the database using a configuration setting name, or exit the
    program with an error that value does not exist or is not a string.
    """

    config = try_get_config_with_setting_name(env.db, setting_name)
    if config is None:
        log_error_exit(
            env,
            f"No configuration value found in the database for setting '{setting_name}'."
        )

    if config.value is None:
        log_error_exit(
            env,
            f"Found a configuration value in the database for setting '{setting_name}' but that value is NULL."
        )

    return config.value
