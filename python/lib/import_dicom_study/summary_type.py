from dataclasses import dataclass
from datetime import date


@dataclass
class DicomStudyPatient:
    """
    Information about a DICOM study patient.
    """

    id:         str
    name:       str
    sex:        str | None
    birth_date: date | None


@dataclass
class DicomStudyScanner:
    """
    Information about a DICOM study scanner.
    """

    manufacturer:     str
    model:            str
    serial_number:    str
    software_version: str


@dataclass
class DicomStudyInfo:
    """
    General information about a DICOM study.
    """

    study_uid:   str
    patient:     DicomStudyPatient
    scanner:     DicomStudyScanner
    scan_date:   date | None
    institution: str | None
    modality:    str


@dataclass
class DicomStudyDicomFile:
    """
    Information about a DICOM file within a DICOM sutdy.
    """

    file_name:          str
    md5_sum:            str
    series_number:      int | None
    series_uid:         str | None
    series_description: str | None
    file_number:        int | None
    echo_number:        int | None
    echo_time:          float | None
    sequence_name:      str | None


@dataclass
class DicomStudyOtherFile:
    """
    Information about a non-DICOM file within a DICOM study.
    """

    file_name: str
    md5_sum:   str


@dataclass
class DicomStudyAcquisition:
    """
    Information about an acquisition within a DICOM study.
    """

    series_number:      int
    series_uid:         str | None
    series_description: str | None
    sequence_name:      str | None
    echo_time:          float | None  # In Milliseconds
    repetition_time:    float | None  # In Milliseconds
    inversion_time:     float | None  # In Milliseconds
    slice_thickness:    float | None  # In Millimeters
    phase_encoding:     str | None
    number_of_files:    int
    modality:           str | None


@dataclass(frozen=True)
class DicomStudyAcquisitionKey:
    """
    Identifying information about an acquisition within a DICOM study.
    """

    series_number: int
    echo_numbers: str | None
    sequence_name: str | None


@dataclass
class DicomStudySummary:
    """
    Information about a DICOM study and its files.
    """

    info: DicomStudyInfo
    acquisitions: list[DicomStudyAcquisition]
    dicom_files: list[DicomStudyDicomFile]
    other_files: list[DicomStudyOtherFile]
