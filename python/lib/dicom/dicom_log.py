from dataclasses import dataclass
from datetime import datetime
import os
import socket
from lib.dicom.text_dict import DictWriter


@dataclass
class DicomArchiveLog:
    """
    DICOM archiving log object, containg information about the archiving of a
    DICOM directory.
    """

    source_path:     str
    target_path:     str
    creator_host:    str
    creator_os:      str
    creator_name:    str
    archive_date:    str
    summary_version: int
    archive_version: int
    tarball_md5_sum: str
    zipball_md5_sum: str
    archive_md5_sum: str


def write_to_string(log: DicomArchiveLog):
    """
    Serialize a DICOM archiving log object into a string.
    """
    return DictWriter([
        ('Taken from dir'                   , log.source_path),
        ('Archive target location'          , log.target_path),
        ('Name of creating host'            , log.creator_host),
        ('Name of host OS'                  , log.creator_os),
        ('Created by user'                  , log.creator_name),
        ('Archived on'                      , log.archive_date),
        ('dicomSummary version'             , log.summary_version),
        ('dicomTar version'                 , log.archive_version),
        ('md5sum for DICOM tarball'         , log.tarball_md5_sum),
        ('md5sum for DICOM tarball gzipped' , log.zipball_md5_sum),
        ('md5sum for complete archive'      , log.archive_md5_sum),
    ]).write()


def write_to_file(file_path: str, log: DicomArchiveLog):
    """
    Serialize a DICOM archiving log object into a text file.
    """
    string = write_to_string(log)
    with open(file_path, 'w') as file:
        file.write(string)


def make(source: str, target: str, tarball_md5_sum: str, zipball_md5_sum: str):
    """
    Create a DICOM archiving log object from the provided arguments on a DICOM
    directory, as well as the current execution environment.
    """
    return DicomArchiveLog(
        source,
        target,
        socket.gethostname(),
        os.uname().sysname,
        os.environ['USER'],
        datetime.strftime(datetime.now(), '%Y-%m-%d %H:%M:%S'),
        2,
        2,
        tarball_md5_sum,
        zipball_md5_sum,
        'Provided in database only',
    )
