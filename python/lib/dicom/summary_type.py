from dataclasses import dataclass
from datetime import date


@dataclass
class Patient:
    """
    DICOM patient object, which contains information about a DICOM patient.
    """

    id:         str
    name:       str
    sex:        str | None
    birth_date: date | None


@dataclass
class Scanner:
    """
    DICOM scanner object, which contains information about a DICOM scanner.
    """

    manufacturer:     str
    model:            str
    serial_number:    str
    software_version: str


@dataclass
class Info:
    """
    General DICOM information object, which contains general information about
    a DICOM directory.
    """

    study_uid:   str
    patient:     Patient
    scanner:     Scanner
    scan_date:   date | None
    institution: str | None
    modality:    str


@dataclass
class DicomFile:
    """
    DICOM file object, which contains information about a DICOM file inside a
    DICOM directory.
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
class OtherFile:
    """
    Non-DICOM file object, which contains information about a non-DICOM file
    inside a DICOM directory.
    """

    file_name: str
    md5_sum:   str


@dataclass
class Acquisition:
    """
    DICOM acquisition object, which contains information about a DICOM series.
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


@dataclass
class Summary:
    """
    DICOM summary object, which contains information about a DICOM directory.
    """

    info: Info
    acquis: list[Acquisition]
    dicom_files: list[DicomFile]
    other_files: list[OtherFile]
