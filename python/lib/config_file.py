"""
This module stores the classes used in the Python configuration file of LORIS-MRI.
"""

import importlib.util
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session as Database

import lib.exitcode
from lib.db.queries.site import get_all_sites


@dataclass
class DatabaseConfig:
    """
    Class wrapping the MariaDB / MySQL database access configuration.
    """

    host:     str
    username: str
    password: str
    database: str
    port:     int = 3306  # Default database port.


@dataclass
class S3Config:
    """
    Class wrapping AWS S3 access configuration.
    """

    aws_access_key_id:     str
    aws_secret_access_key: str
    aws_s3_endpoint_url:   str | None = None  # Can also be obtained from the database.
    aws_s3_bucket_name:    str | None = None  # Can also be obtained from the database.


@dataclass
class CreateSessionConfig:
    """
    Configuration information used to create the session of a candidate scan.
    """

    site: str
    """
    Alias of the session site.
    """

    project: str
    """
    Alias of the session project.
    """

    cohort: str
    """
    Name of the session cohort.
    """


@dataclass
class SessionCandidateConfig:
    """
    Configuration information used to identify the session of a candidate scan.
    """

    psc_id: str
    cand_id: int
    visit_label: str
    create_session: CreateSessionConfig | None


@dataclass
class SessionPhantomConfig:
    """
    Configuration information used to register a phantom scan.
    """

    name: str
    """
    Name of the phantom scan.
    """

    site: str
    """
    Alias of the phantom site.
    """

    project: str
    """
    Alias of the phantom project.
    """


# TODO: Replace with type alias in Python 3.12.
SessionConfig = SessionCandidateConfig | SessionPhantomConfig


def load_config(arg: str | None) -> Any:
    """
    Load the LORIS-MRI Python configuration file from the environment or exit the program with an
    error if that file is not found or cannot be loaded.
    """

    config_dir_path_value = os.environ.get('LORIS_CONFIG')
    if config_dir_path_value is None:
        print("ERROR: Environment variable 'LORIS_CONFIG' not set.", file=sys.stderr)
        sys.exit(lib.exitcode.INVALID_ENVIRONMENT_VAR)

    # Get the name of the configuration file from the argument or use the default name.
    config_file_name = arg if arg is not None else 'config.py'

    config_dir_path = Path(config_dir_path_value).resolve()
    config_file_path = (config_dir_path / config_file_name).resolve()

    if not config_file_path.is_relative_to(config_dir_path):
        print(
            (
                f"ERROR: The configuration file value '{config_file_name}' is outside of the LORIS configuration"
                " directory."
            ),
            file=sys.stderr,
        )

        sys.exit(lib.exitcode.INVALID_PATH)

    if not config_file_path.exists():
        print(
            f"ERROR: No configuration file '{config_file_name}' found in the '{config_dir_path}' directory.",
            file=sys.stderr,
        )

        sys.exit(lib.exitcode.INVALID_PATH)

    # Use the stem of the configuration file as the module name.
    spec = importlib.util.spec_from_file_location(config_file_path.stem, config_file_path)
    if spec is None or spec.loader is None:
        print(f"ERROR: Cannot load module specification for configuration file '{config_file_name}'.", file=sys.stderr)
        sys.exit(lib.exitcode.INVALID_IMPORT)

    # Load the configuration module.
    config = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(config)
    return config


def try_get_site_id_with_patient_id_heuristic(db: Database, patient_id: str) -> int | None:
    """
    Try to get the ID of a session's site based on its patient ID. This function is a heuristic
    that is provided for older projects to ease their transition to the new session configuration
    format, it should not be used in new projects.
    """

    sites = get_all_sites(db)
    for site in sites:
        if site.alias in patient_id:
            return site.id

    return None
