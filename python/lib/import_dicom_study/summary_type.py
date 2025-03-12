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

    manufacturer:     str | None
    model:            str | None
    serial_number:    str | None
    software_version: str | None


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


# This dataclass does not correspond to a "real" DICOM series, as a DICOM series may actually have
# files that have different echo times, inversion times, repetition times... (for instance in
# multi-echo series).
# Generally, a "real" DICOM series should be uniquely identifiable by using the series instance UID
# DICOM attribute.
# This class corresponds more to a LORIS database DICOM series entry, which is a unique tuple of
# some parameters of the DICOM files of a study (including the DICOM series instance UID). As such,
# there is a 1-to-n relationship between a "real" DICOM series, and the LORIS database DICOM series
# entries.
@dataclass(frozen=True)
class DicomStudyDicomSeries:
    """
    Information about an DICOM series within a DICOM study.
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
    modality:           str | None


@dataclass
class DicomStudySummary:
    """
    Information about a DICOM study and its files.
    """

    info: DicomStudyInfo
    dicom_series_files: dict[DicomStudyDicomSeries, list[DicomStudyDicomFile]]
    other_files: list[DicomStudyOtherFile]
