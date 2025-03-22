"""
This module stores the classes used in the Python configuration file of LORIS-MRI.
"""

from dataclasses import dataclass

from sqlalchemy.orm import Session as Database

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

    site_id:    int
    project_id: int
    cohort_id:  int


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
    site_id: int
    project_id: int


# TODO: Replace with type alias in Python 3.12.
SessionConfig = SessionCandidateConfig | SessionPhantomConfig


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
        elif site.mri_alias in patient_id:
            return site.id

    return None
