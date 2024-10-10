"""
This module stores the classes used in the Python configuration file of LORIS-MRI.
"""

from dataclasses import dataclass


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
class CreateVisitInfo:
    """
    Class wrapping the parameters for automated visit creation (in the `Visit_Windows` table).
    """

    project_id: int
    cohort_id:  int


@dataclass
class SubjectInfo:
    """
    Dataclass wrapping information about a subject configuration, including information about the
    candidate, the visit label, and the automated visit creation (or not).
    """

    # The name of the subject may be either the DICOM's PatientName or PatientID depending on the
    # LORIS configuration.
    name: str
    is_phantom: bool
    # For a phantom scan, the PSCID is 'scanner'.
    psc_id: str
    # For a phantom scan, the CandID is that of the scanner.
    cand_id: int
    visit_label: str
    # `CreateVisitInfo` means that a visit can be created automatically using the parameters
    # provided, `None` means that the visit needs to already exist in the database.
    create_visit: CreateVisitInfo | None

    @staticmethod
    def from_candidate(
        name: str,
        psc_id: str,
        cand_id: int,
        visit_label: str,
        create_visit: CreateVisitInfo | None,
    ):
        return SubjectInfo(name, False, psc_id, cand_id, visit_label, create_visit)

    @staticmethod
    def from_phantom(
        name: str,
        cand_id: int,
        visit_label: str,
        create_visit: CreateVisitInfo | None,
    ):
        return SubjectInfo(name, True, 'scanner', cand_id, visit_label, create_visit)
