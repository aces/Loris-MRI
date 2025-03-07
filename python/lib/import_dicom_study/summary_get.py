import os
from functools import cmp_to_key

import pydicom
import pydicom.errors

from lib.import_dicom_study.summary_type import (
    DicomStudyAcquisition,
    DicomStudyAcquisitionKey,
    DicomStudyDicomFile,
    DicomStudyInfo,
    DicomStudyOtherFile,
    DicomStudyPatient,
    DicomStudyScanner,
    DicomStudySummary,
)
from lib.import_dicom_study.text import read_dicom_date_none
from lib.util.crypto import compute_file_md5_hash
from lib.util.fs import iter_all_dir_files


def get_dicom_study_summary(dicom_study_dir_path: str, verbose: bool):
    """
    Get information about a DICOM study by reading the files in the DICOM study directory.
    """

    study_info = None
    dicom_files: list[DicomStudyDicomFile] = []
    other_files: list[DicomStudyOtherFile] = []
    acquisitions_dict: dict[DicomStudyAcquisitionKey, DicomStudyAcquisition] = dict()

    file_rel_paths = list(iter_all_dir_files(dicom_study_dir_path))
    for i, file_rel_path in enumerate(file_rel_paths, start=1):
        if verbose:
            print(f"Processing file '{file_rel_path}' ({i}/{len(file_rel_paths)})")

        file_path = os.path.join(dicom_study_dir_path, file_rel_path)

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

            dicom_files.append(get_dicom_file_info(dicom))

            acquisition_key = DicomStudyAcquisitionKey(
                series_number = dicom.SeriesNumber,
                echo_numbers  = read_value_none(dicom, 'EchoNumbers'),
                sequence_name = read_value_none(dicom, 'SequenceName'),
            )

            if acquisition_key not in acquisitions_dict:
                acquisitions_dict[acquisition_key] = get_acquisition_info(dicom)

            acquisitions_dict[acquisition_key].number_of_files += 1
        except pydicom.errors.InvalidDicomError:
            other_files.append(get_other_file_info(file_path))

    if study_info is None:
        raise Exception("Found no DICOM file in the DICOM study directory.")

    acquisitions = list(acquisitions_dict.values())

    dicom_files.sort(key=cmp_to_key(compare_dicom_files))
    acquisitions.sort(key=cmp_to_key(compare_acquisitions))

    return DicomStudySummary(study_info, acquisitions, dicom_files, other_files)


def get_dicom_study_info(dicom: pydicom.Dataset) -> DicomStudyInfo:
    """
    Get general information about a DICOM study from one of its DICOM files.
    """

    birth_date = read_dicom_date_none(read_value_none(dicom, 'PatientBirthDate'))
    scan_date  = read_dicom_date_none(read_value_none(dicom, 'StudyDate'))

    patient = DicomStudyPatient(
        read_value(dicom, 'PatientID'),
        read_value(dicom, 'PatientName'),
        read_value_none(dicom, 'PatientSex'),
        birth_date,
    )

    scanner = DicomStudyScanner(
        read_value(dicom, 'Manufacturer'),
        read_value(dicom, 'ManufacturerModelName'),
        read_value(dicom, 'DeviceSerialNumber'),
        read_value(dicom, 'SoftwareVersions'),
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


def get_other_file_info(file_path: str) -> DicomStudyOtherFile:
    """
    Get information about a non-DICOM file within a DICOM study.
    """

    return DicomStudyOtherFile(
        os.path.basename(file_path),
        compute_file_md5_hash(file_path),
    )


def get_acquisition_info(dicom: pydicom.Dataset):
    """
    Get information about an acquisition within a DICOM study.
    """

    return DicomStudyAcquisition(
        read_value(dicom, 'SeriesNumber'),
        read_value_none(dicom, 'SeriesInstanceUID'),
        read_value_none(dicom, 'SeriesDescription'),
        read_value_none(dicom, 'SequenceName'),
        read_value_none(dicom, 'EchoTime'),
        read_value_none(dicom, 'RepetitionTime'),
        read_value_none(dicom, 'InversionTime'),
        read_value_none(dicom, 'SliceThickness'),
        read_value_none(dicom, 'InPlanePhaseEncodingDirection'),
        0,
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
        return None

    return dicom[tag].value or None


# Comparison functions used to sort the various DICOM study information objects.

def compare_dicom_files(a: DicomStudyDicomFile, b: DicomStudyDicomFile):
    """
    Compare two DICOM file informations in accordance with `functools.cmp_to_key`.
    """

    return \
        compare_int_none(a.series_number, b.series_number) or \
        compare_int_none(a.file_number, b.file_number) or \
        compare_int_none(a.echo_number, b.echo_number)


def compare_acquisitions(a: DicomStudyAcquisition, b: DicomStudyAcquisition):
    """
    Compare two acquisition informations in accordance with `functools.cmp_to_key`.
    """

    return \
        a.series_number - b.series_number or \
        compare_string_none(a.sequence_name, b.sequence_name)


def compare_int_none(a: int | None, b: int | None):
    """
    Compare two nullable integers in accordance with `functools.cmp_to_key`.
    """

    match a, b:
        case None, None:
            return 0
        case _, None:
            return -1
        case None, _:
            return 1
        case a, b:
            return a - b


def compare_string_none(a: str | None, b: str | None):
    """
    Compare two nullable strings in accordance with `functools.cmp_to_key`.
    """

    match a, b:
        case None, None:
            return 0
        case _, None:
            return -1
        case None, _:
            return 1
        case a, b if a < b:
            return -1
        case a, b if a > b:
            return 1
        case a, b:
            return 0
