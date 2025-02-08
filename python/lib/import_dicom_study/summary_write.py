import xml.etree.ElementTree as ET

from lib.import_dicom_study.summary_type import (
    DicomStudyAcquisition,
    DicomStudyDicomFile,
    DicomStudyInfo,
    DicomStudyOtherFile,
    DicomStudySummary,
)
from lib.import_dicom_study.text import write_date_none
from lib.import_dicom_study.text_dict import DictWriter
from lib.import_dicom_study.text_table import TableWriter


def write_dicom_study_summary_to_file(dicom_summary: DicomStudySummary, filename: str):
    """
    Serialize a DICOM study summary object into a text file.
    """

    string = write_dicom_study_summary(dicom_summary)
    with open(filename, 'w') as file:
        file.write(string)


def write_dicom_study_summary(dicom_summary: DicomStudySummary) -> str:
    """
    Serialize a DICOM study summary object into a string.
    """

    xml = ET.Element('STUDY')
    ET.SubElement(xml, 'STUDY_INFO').text   = write_dicom_study_info(dicom_summary.info)
    ET.SubElement(xml, 'FILES').text        = write_dicom_study_dicom_files(dicom_summary.dicom_files)
    ET.SubElement(xml, 'OTHERS').text       = write_dicom_study_other_files(dicom_summary.other_files)
    ET.SubElement(xml, 'ACQUISITIONS').text = write_dicom_study_acquisitions(dicom_summary.acquisitions)
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


def write_dicom_study_dicom_files(dicom_files: list[DicomStudyDicomFile]) -> str:
    """
    Serialize information about the DICOM files of a DICOM study into a table.
    """

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


def write_dicom_study_acquisitions(acquisitions: list[DicomStudyAcquisition]) -> str:
    """
    Serialize information about the acquisitions of a DICOM study into a table.
    """

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

    for acquisition in acquisitions:
        writer.append_row([
            acquisition.series_number,
            acquisition.series_description,
            acquisition.sequence_name,
            acquisition.echo_time,
            acquisition.repetition_time,
            acquisition.inversion_time,
            acquisition.slice_thickness,
            acquisition.phase_encoding,
            acquisition.number_of_files,
            acquisition.series_uid,
            acquisition.modality,
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

    return '\n' + DictWriter([
        ('Total number of files', len(dicom_summary.dicom_files) + len(dicom_summary.other_files)),
        ('Age at scan', age),
    ]).write()
