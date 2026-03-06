import xml.etree.ElementTree as ET
from functools import cmp_to_key
from pathlib import Path

from loris_utils.iter import count, flatten

from lib.import_dicom_study.summary_type import (
    DicomStudyDicomFile,
    DicomStudyDicomSeries,
    DicomStudyInfo,
    DicomStudyOtherFile,
    DicomStudySummary,
)
from lib.import_dicom_study.text import write_date_none
from lib.import_dicom_study.text_dict import DictWriter
from lib.import_dicom_study.text_table import TableWriter


def write_dicom_study_summary_to_file(dicom_summary: DicomStudySummary, file_path: Path):
    """
    Serialize a DICOM study summary object into a text file.
    """

    summary = write_dicom_study_summary(dicom_summary)
    with open(file_path, 'w') as file:
        file.write(summary)


def write_dicom_study_summary(dicom_summary: DicomStudySummary) -> str:
    """
    Serialize a DICOM study summary object into a string.
    """

    xml = ET.Element('STUDY')
    ET.SubElement(xml, 'STUDY_INFO').text   = write_dicom_study_info(dicom_summary.info)
    ET.SubElement(xml, 'FILES').text        = write_dicom_study_dicom_files(dicom_summary.dicom_series_files)
    ET.SubElement(xml, 'OTHERS').text       = write_dicom_study_other_files(dicom_summary.other_files)
    ET.SubElement(xml, 'ACQUISITIONS').text = write_dicom_study_dicom_series(dicom_summary.dicom_series_files)
    ET.SubElement(xml, 'SUMMARY').text      = write_dicom_study_ending(dicom_summary)
    ET.indent(xml, space='')
    return ET.tostring(xml, encoding='unicode') + '\n'


def write_dicom_study_info(info: DicomStudyInfo) -> str:
    """
    Serialize general information about a DICOM study.
    """

    return '\n' + DictWriter([
        ('Unique Study ID'          , info.study_uid),
        ('Patient Name'             , info.patient.name),
        ('Patient ID'               , info.patient.id),
        ('Patient date of birth'    , write_date_none(info.patient.birth_date)),
        ('Patient Sex'              , info.patient.sex),
        ('Scan Date'                , write_date_none(info.scan_date)),
        ('Scanner Manufacturer'     , info.scanner.manufacturer),
        ('Scanner Model Name'       , info.scanner.model),
        ('Scanner Serial Number'    , info.scanner.serial_number),
        ('Scanner Software Version' , info.scanner.software_version),
        ('Institution Name'         , info.institution),
        ('Modality'                 , info.modality),
    ]).write()


def write_dicom_study_dicom_files(dicom_series_files: dict[DicomStudyDicomSeries, list[DicomStudyDicomFile]]) -> str:
    """
    Serialize information about the DICOM files of a DICOM study into a table.
    """

    dicom_files = list(flatten(dicom_series_files.values()))
    dicom_files.sort(key=cmp_to_key(compare_dicom_files))

    writer = TableWriter()
    writer.append_row(['SN', 'FN', 'EN', 'Series', 'md5sum', 'File name'])
    for dicom_file in dicom_files:
        writer.append_row([
            dicom_file.series_number,
            dicom_file.file_number,
            dicom_file.echo_number,
            dicom_file.series_description,
            dicom_file.md5_sum,
            dicom_file.file_name,
        ])

    return '\n' + writer.write()


def write_dicom_study_other_files(other_files: list[DicomStudyOtherFile]) -> str:
    """
    Serialize information about the non-DICOM files of a DICOM study into a table.
    """

    writer = TableWriter()
    writer.append_row(['md5sum', 'File name'])
    for other_file in other_files:
        writer.append_row([
            other_file.md5_sum,
            other_file.file_name,
        ])

    return '\n' + writer.write()


def write_dicom_study_dicom_series(dicom_series_files: dict[DicomStudyDicomSeries, list[DicomStudyDicomFile]]) -> str:
    """
    Serialize information about the DICOM series of a DICOM study into a table.
    """

    dicom_series_list = list(dicom_series_files.keys())
    dicom_series_list.sort(key=cmp_to_key(compare_dicom_series))

    writer = TableWriter()
    writer.append_row([
        'Series (SN)',
        'Name of series',
        'Seq Name',
        'echoT ms',
        'repT ms',
        'invT ms',
        'sth mm',
        'PhEnc',
        'NoF',
        'Series UID',
        'Mod'
    ])

    for dicom_series in dicom_series_list:
        dicom_files = dicom_series_files[dicom_series]

        writer.append_row([
            dicom_series.series_number,
            dicom_series.series_description,
            dicom_series.sequence_name,
            dicom_series.echo_time,
            dicom_series.repetition_time,
            dicom_series.inversion_time,
            dicom_series.slice_thickness,
            dicom_series.phase_encoding,
            len(dicom_files),
            dicom_series.series_uid,
            dicom_series.modality,
        ])

    return '\n' + writer.write()


def write_dicom_study_ending(dicom_summary: DicomStudySummary) -> str:
    """
    Serialize some additional information about a DICOM study.
    """

    birth_date = dicom_summary.info.patient.birth_date
    scan_date  = dicom_summary.info.scan_date

    if birth_date and scan_date:
        years  = scan_date.year  - birth_date.year
        months = scan_date.month - birth_date.month
        days   = scan_date.day   - birth_date.day
        total  = round(years + months / 12 + days / 365.0, 2)
        age = f'{total} or {years} years, {months} months {days} days'
    else:
        age = ''

    dicom_files_count = count(flatten(dicom_summary.dicom_series_files.values()))
    other_files_count = len(dicom_summary.other_files)

    return '\n' + DictWriter([
        ('Total number of files', dicom_files_count + other_files_count),
        ('Age at scan', age),
    ]).write()


# Comparison functions used to sort the various DICOM study information objects.

def compare_dicom_files(a: DicomStudyDicomFile, b: DicomStudyDicomFile):
    """
    Compare two DICOM file informations in accordance with `functools.cmp_to_key`.
    """

    return \
        compare_int_none(a.series_number, b.series_number) or \
        compare_int_none(a.file_number, b.file_number) or \
        compare_int_none(a.echo_number, b.echo_number)


def compare_dicom_series(a: DicomStudyDicomSeries, b: DicomStudyDicomSeries):
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
