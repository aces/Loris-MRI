import xml.etree.ElementTree as ET
from lib.dicom.summary_type import Summary, Info, Acquisition, DicomFile, OtherFile
from lib.dicom.text_dict import DictWriter
from lib.dicom.text_table import TableWriter
from lib.dicom.text import write_date_none


def write_to_file(filename: str, summary: Summary):
    """
    Serialize a DICOM summary object into a text file.
    """
    string = write_to_string(summary)
    with open(filename, 'w') as file:
        file.write(string)


def write_to_string(summary: Summary) -> str:
    """
    Serialize a DICOM summary object into a string.
    """
    return ET.tostring(write_xml(summary), encoding='unicode') + '\n'


def write_xml(summary: Summary):
    study = ET.Element('STUDY')
    ET.SubElement(study, 'STUDY_INFO').text   = write_info(summary.info)
    ET.SubElement(study, 'FILES').text        = write_dicom_files_table(summary.dicom_files)
    ET.SubElement(study, 'OTHERS').text       = write_other_files_table(summary.other_files)
    ET.SubElement(study, 'ACQUISITIONS').text = write_acquis_table(summary.acquis)
    ET.SubElement(study, 'SUMMARY').text      = write_ending(summary)
    ET.indent(study, space='')
    return study


def write_info(info: Info):
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


def write_dicom_files_table(files: list[DicomFile]):
    writer = TableWriter()
    writer.append_row(['SN', 'FN', 'EN', 'Series', 'md5sum', 'File name'])
    for file in files:
        writer.append_row([
            file.series_number,
            file.file_number,
            file.echo_number,
            file.series_description,
            file.md5_sum,
            file.file_name,
        ])

    return '\n' + writer.write()


def write_other_files_table(files: list[OtherFile]):
    writer = TableWriter()
    writer.append_row(['md5sum', 'File name'])
    for file in files:
        writer.append_row([
            file.md5_sum,
            file.file_name,
        ])

    return '\n' + writer.write()


def write_acquis_table(acquis: list[Acquisition]):
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

    for acqui in acquis:
        writer.append_row([
            acqui.series_number,
            acqui.series_description,
            acqui.sequence_name,
            acqui.echo_time,
            acqui.repetition_time,
            acqui.inversion_time,
            acqui.slice_thickness,
            acqui.phase_encoding,
            acqui.number_of_files,
            acqui.series_uid,
            acqui.modality,
        ])

    return '\n' + writer.write()


def write_ending(summary: Summary):
    birth_date = summary.info.patient.birth_date
    scan_date  = summary.info.scan_date

    if birth_date and scan_date:
        years  = scan_date.year  - birth_date.year
        months = scan_date.month - birth_date.month
        days   = scan_date.day   - birth_date.day
        total  = round(years + months / 12 + days / 365.0, 2)
        age = f'{total} or {years} years, {months} months {days} days'
    else:
        age = ''

    return '\n' + DictWriter([
        ('Total number of files', len(summary.dicom_files) + len(summary.other_files)),
        ('Age at scan', age),
    ]).write()
