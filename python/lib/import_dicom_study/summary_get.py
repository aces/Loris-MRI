import os
from pathlib import Path

import pydicom
import pydicom.errors
from loris_utils.crypto import compute_file_md5_hash
from loris_utils.fs import iter_all_dir_files

from lib.import_dicom_study.summary_type import (
    DicomStudyDicomFile,
    DicomStudyDicomSeries,
    DicomStudyInfo,
    DicomStudyOtherFile,
    DicomStudyPatient,
    DicomStudyScanner,
    DicomStudySummary,
)
from lib.import_dicom_study.text import read_dicom_date_none


def get_dicom_study_summary(dicom_study_dir_path: Path, verbose: bool):
    """
    Get information about a DICOM study by reading the files in the DICOM study directory.
    """

    study_info = None
    dicom_series_files: dict[DicomStudyDicomSeries, list[DicomStudyDicomFile]] = {}
    other_files: list[DicomStudyOtherFile] = []

    file_rel_paths = list(iter_all_dir_files(dicom_study_dir_path))
    for i, file_rel_path in enumerate(file_rel_paths, start=1):
        if verbose:
            print(f"Processing file '{file_rel_path}' ({i}/{len(file_rel_paths)})")

        file_path = dicom_study_dir_path / file_rel_path

        try:
            dicom = pydicom.dcmread(file_path)  # type: ignore
            if study_info is None:
                study_info = get_dicom_study_info(dicom)

            modality = read_value_none(dicom, 'Modality')
            if modality is None:
                print(f"Found no modality for DICOM file '{file_rel_path}'.")
                raise pydicom.errors.InvalidDicomError

            if modality != 'MR' and modality != 'PT':
                print(f"Found unhandled modality '{modality}' for DICOM file '{file_rel_path}'.")
                raise pydicom.errors.InvalidDicomError

            dicom_series = get_dicom_series_info(dicom)
            if dicom_series not in dicom_series_files:
                dicom_series_files[dicom_series] = []

            dicom_file = get_dicom_file_info(dicom)
            dicom_series_files[dicom_series].append(dicom_file)
        except pydicom.errors.InvalidDicomError:
            other_files.append(get_other_file_info(file_path))

    if study_info is None:
        raise Exception("Found no DICOM file in the DICOM study directory.")

    return DicomStudySummary(study_info, dicom_series_files, other_files)


def get_dicom_study_info(dicom: pydicom.Dataset) -> DicomStudyInfo:
    """
    Get general information about a DICOM study from one of its DICOM files.
    """

    birth_date = read_dicom_date_none(read_value_none(dicom, 'PatientBirthDate'))
    scan_date  = read_dicom_date_none(read_value_none(dicom, 'StudyDate'))

    patient = DicomStudyPatient(
        str(read_value(dicom, 'PatientID')),
        str(read_value(dicom, 'PatientName')),
        read_value_none(dicom, 'PatientSex'),
        birth_date,
    )

    scanner = DicomStudyScanner(
        read_value_none(dicom, 'Manufacturer'),
        read_value_none(dicom, 'ManufacturerModelName'),
        read_value_none(dicom, 'DeviceSerialNumber'),
        read_value_none(dicom, 'SoftwareVersions'),
    )

    return DicomStudyInfo(
        read_value(dicom, 'StudyInstanceUID'),
        patient,
        scanner,
        scan_date,
        read_value_none(dicom, 'InstitutionName'),
        read_value(dicom, 'Modality'),
    )


def get_dicom_file_info(dicom: pydicom.Dataset) -> DicomStudyDicomFile:
    """
    Get information about a DICOM file within a DICOM study.
    """

    return DicomStudyDicomFile(
        os.path.basename(dicom.filename),
        compute_file_md5_hash(dicom.filename),
        read_value_none(dicom, 'SeriesNumber'),
        read_value_none(dicom, 'SeriesInstanceUID'),
        read_value_none(dicom, 'SeriesDescription'),
        read_value_none(dicom, 'InstanceNumber'),
        read_value_none(dicom, 'EchoNumbers'),
        read_value_none(dicom, 'EchoTime'),
        read_value_none(dicom, 'SequenceName'),
    )


def get_other_file_info(file_path: Path) -> DicomStudyOtherFile:
    """
    Get information about a non-DICOM file within a DICOM study.
    """

    return DicomStudyOtherFile(
        file_path.name,
        compute_file_md5_hash(file_path),
    )


def get_dicom_series_info(dicom: pydicom.Dataset):
    """
    Get information about a DICOM series within a DICOM study.
    """

    return DicomStudyDicomSeries(
        read_value(dicom, 'SeriesNumber'),
        read_value_none(dicom, 'SeriesInstanceUID'),
        read_value_none(dicom, 'SeriesDescription'),
        read_value_none(dicom, 'SequenceName'),
        read_value_none(dicom, 'EchoTime'),
        read_value_none(dicom, 'RepetitionTime'),
        read_value_none(dicom, 'InversionTime'),
        read_value_none(dicom, 'SliceThickness'),
        read_value_none(dicom, 'InPlanePhaseEncodingDirection'),
        read_value_none(dicom, 'Modality'),
    )


# Read DICOM attributes.

def read_value(dicom: pydicom.Dataset, tag: str):
    """
    Read a DICOM attribute from a DICOM using a given tag, or raise an exception if there is no
    attribute with that tag in the DICOM.
    """

    if tag not in dicom:
        raise Exception(f"Expected DICOM tag '{tag}' but found none.")

    return dicom[tag].value


def read_value_none(dicom: pydicom.Dataset, tag: str):
    """
    Read a DICOM attribute from a DICOM using a given tag, or return `None` if there is no
    attribute with that tag in the DICOM.
    """

    if tag not in dicom:
        for elem in dicom.iterall():
            # to find header information in enhanced DICOMs, need to look into subheaders
            if elem.tag == tag:
                return elem.value
        return None

    return dicom[tag].value or None
