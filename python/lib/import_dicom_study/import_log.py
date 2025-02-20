import os
import socket
from dataclasses import dataclass
from datetime import datetime

from lib.import_dicom_study.text_dict import DictWriter


@dataclass
class DicomStudyImportLog:
    """
    Information about the past import of a DICOM study.
    """

    source_path: str
    target_path: str
    creator_host: str
    creator_os: str
    creator_name: str
    archive_date: str
    summary_version: int
    archive_version: int
    tarball_md5_sum: str
    zipball_md5_sum: str
    archive_md5_sum: str


def write_dicom_study_import_log_to_string(import_log: DicomStudyImportLog):
    """
    Serialize a DICOM study import log into a string.
    """

    return DictWriter([
        ("Taken from dir",                   import_log.source_path),
        ("Archive target location",          import_log.target_path),
        ("Name of creating host",            import_log.creator_host),
        ("Name of host OS",                  import_log.creator_os),
        ("Created by user",                  import_log.creator_name),
        ("Archived on",                      import_log.archive_date),
        ("dicomSummary version",             import_log.summary_version),
        ("dicomTar version",                 import_log.archive_version),
        ("md5sum for DICOM tarball",         import_log.tarball_md5_sum),
        ("md5sum for DICOM tarball gzipped", import_log.zipball_md5_sum),
        ("md5sum for complete archive",      import_log.archive_md5_sum),
    ]).write()


def write_dicom_study_import_log_to_file(import_log: DicomStudyImportLog, file_path: str):
    """
    Serialize a DICOM study import log into a text file.
    """

    string = write_dicom_study_import_log_to_string(import_log)
    with open(file_path, "w") as file:
        file.write(string)


def make_dicom_study_import_log(source: str, target: str, tarball_md5_sum: str, zipball_md5_sum: str):
    """
    Create a DICOM study import log from the provided arguments about a DICOM study, as well as the
    current execution environment.
    """

    return DicomStudyImportLog(
        source,
        target,
        socket.gethostname(),
        os.uname().sysname,
        os.environ["USER"],
        datetime.strftime(datetime.now(), "%Y-%m-%d %H:%M:%S"),
        2,
        2,
        tarball_md5_sum,
        zipball_md5_sum,
        "Provided in database only",
    )
