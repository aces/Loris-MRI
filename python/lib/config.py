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
    check_loris_directory(env, data_dir_path, "data")
    return data_dir_path


def get_dicom_archive_dir_path_config(env: Env) -> Path:
    """
    Get the LORIS DICOM archive directory path from the in-database configuration, or exit the
    program with an error if that configuration value does not exist or is incorrect.
    """

    dicom_archive_dir_path = Path(_get_config_value(env, 'tarchiveLibraryDir'))
    check_loris_directory(env, dicom_archive_dir_path, "DICOM archive")
    return dicom_archive_dir_path


def get_default_bids_visit_label_config(env: Env) -> str | None:
    """
    Get the default BIDS visit label from the in-database configuration.
    """

    return _try_get_config_value(env, 'default_bids_vl')


def get_ephys_visualization_enabled_config(env: Env) -> bool:
    """
    Get whether the electrophysiology visualization is enabled from the in-database configuration.
    """

    visualization_enabled = _try_get_config_value(env, 'useEEGBrowserVisualizationComponents')
    return visualization_enabled == 'true' or visualization_enabled == '1'


def get_ephys_chunks_dir_path_config(env: Env) -> Path | None:
    """
    Get the electrophysiology chunks directory path configuration value from the in-database
    configuration.
    """

    ephys_chunks_path = _try_get_config_value(env, 'EEGChunksPath')
    if ephys_chunks_path is None:
        return None

    ephys_chunks_path = Path(ephys_chunks_path)
    check_loris_directory(env, ephys_chunks_path, "electrophysiology chunks")
    return ephys_chunks_path


def get_ephys_archive_dir_path_config(env: Env) -> Path | None:
    """
    Get the electrophysiology archive directory path configuration value from the in-database
    configuration.
    """

    ephys_archive_dir_path = _try_get_config_value(env, 'prePackagedDownloadPath')
    if ephys_archive_dir_path is None:
        return None

    ephys_archive_dir_path = Path(ephys_archive_dir_path)
    check_loris_directory(env, ephys_archive_dir_path, "electrophysiology archive")
    return ephys_archive_dir_path


def check_loris_directory(env: Env, dir_path: Path, display_name: str):
    """
    Check that a LORIS directory exists and is readable and writable, or exit the program with an
    error otherwise.
    """

    if not dir_path.is_dir():
        log_error_exit(
            env,
            (
                f"The LORIS {display_name} directory path configuration value '{dir_path}' does not refer to an"
                " existing directory."
            ),
        )

    if not os.access(dir_path, os.R_OK) or not os.access(dir_path, os.W_OK):
        log_error_exit(
            env,
            f"Missing read or write permission on the {display_name} directory '{dir_path}'.",
        )


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
