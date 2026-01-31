import os
from pathlib import Path
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


def get_data_dir_path_config(env: Env) -> Path:
    """
    Get the LORIS base data directory path from the in-database configuration, or exit the program
    with an error if that configuration value does not exist or is incorrect.
    """

    data_dir_path = Path(_get_config_value(env, 'dataDirBasepath'))

    if not data_dir_path.is_dir():
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


def get_dicom_archive_dir_path_config(env: Env) -> Path:
    """
    Get the LORIS DICOM archive directory path from the in-database configuration, or exit the
    program with an error if that configuration value does not exist or is incorrect.
    """

    dicom_archive_dir_path = Path(_get_config_value(env, 'tarchiveLibraryDir'))

    if not dicom_archive_dir_path.is_dir():
        log_error_exit(
            env,
            (
                f"The LORIS DICOM archive directory path configuration value '{dicom_archive_dir_path}' does not refer"
                " to an existing directory."
            ),
        )

    if not os.access(dicom_archive_dir_path, os.R_OK) or not os.access(dicom_archive_dir_path, os.W_OK):
        log_error_exit(
            env,
            f"Missing read or write permission on the LORIS DICOM archive directory '{dicom_archive_dir_path}'.",
        )

    return dicom_archive_dir_path


def get_default_bids_visit_label_config(env: Env) -> str | None:
    """
    Get the default BIDS visit label from the in-database configuration.
    """

    return _try_get_config_value(env, 'default_bids_vl')


def get_eeg_viz_enabled_config(env: Env) -> bool:
    """
    Get whether the EEG visualization is enabled from the in-database configuration.
    """

    eeg_viz_enabled = _try_get_config_value(env, 'useEEGBrowserVisualizationComponents')
    return eeg_viz_enabled == 'true' or eeg_viz_enabled == '1'


def get_eeg_chunks_dir_path_config(env: Env) -> Path | None:
    """
    Get the EEG chunks directory path configuration value from the in-database configuration.
    """

    eeg_chunks_path = _try_get_config_value(env, 'EEGChunksPath')
    if eeg_chunks_path is None:
        return None

    eeg_chunks_path = Path(eeg_chunks_path)

    if not eeg_chunks_path.is_dir():
        log_error_exit(
            env,
            (
                f"The configuration value for the LORIS EEG chunks directory path '{eeg_chunks_path}' does not refer to"
                " an existing directory."
            ),
        )

    if not os.access(eeg_chunks_path, os.R_OK) or not os.access(eeg_chunks_path, os.W_OK):
        log_error_exit(
            env,
            f"Missing read or write permission on the LORIS EEG chunks directory '{eeg_chunks_path}'.",
        )

    return eeg_chunks_path


def get_eeg_pre_package_download_dir_path_config(env: Env) -> Path | None:
    """
    Get the EEG pre-packaged download path configuration value from the in-database configuration.
    """

    eeg_pre_package_path = _try_get_config_value(env, 'prePackagedDownloadPath')
    if eeg_pre_package_path is None:
        return None

    eeg_pre_package_path = Path(eeg_pre_package_path)

    if not eeg_pre_package_path.is_dir():
        log_error_exit(
            env,
            (
                "The configuration value for the LORIS EEG pre-packaged download directory path"
                f" '{eeg_pre_package_path}' does not refer to an existing directory."
            ),
        )

    if not os.access(eeg_pre_package_path, os.R_OK) or not os.access(eeg_pre_package_path, os.W_OK):
        log_error_exit(
            env,
            (
                "Missing read or write permission on the LORIS EEG pre-packaged download directory"
                f" '{eeg_pre_package_path}'."
            ),
        )

    return eeg_pre_package_path


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


def _try_get_config_value(env: Env, setting_name: str) -> str | None:
    """
    Get a configuration value from the database using a configuration setting name, or return
    `None` if that configuration setting or value does not exist in the database.
    """

    config = try_get_config_with_setting_name(env.db, setting_name)
    return config.value if config is not None else None
