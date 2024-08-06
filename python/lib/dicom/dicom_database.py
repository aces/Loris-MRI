from datetime import datetime
from typing import Any

from lib.database import Database
from lib.dicom.summary_type import Summary
from lib.dicom.dicom_log import DicomArchiveLog
import lib.dicom.text
import lib.dicom.summary_write
import lib.dicom.dicom_log


def select_dict(db: Database, fields: list[str], table: str, conds: dict[str, Any]):
    """
    Select a record in a table, using a dictionary to specify the conditions \
    needed to update a record.

    :param db: The database.
    :param fields: A list of field names to retrieve.
    :param table: The table name.
    :param conds: A dictionary mapping field names to their current values to \
        determine the records to be updated. \
        Other forms of conditions are not supported by this function.

    :returns: The list of matching records.
    """

    query_conds  = map(
        lambda key, value: key + (' = ' if value is not None else ' IS ') + '%s',
        conds.keys(),
        conds.values(),
    )

    query = f'SELECT {", ".join(fields)} FROM {table} WHERE {" AND ".join(query_conds)}'
    return db.pselect(query, [*conds.values()])


def insert_dict(db: Database, table: str, attrs: dict[str, Any]):
    """
    Insert a record in a table, using a dictionary to specify the attributes of
    the record.

    :param db: The database.
    :param table: The table name.
    :param attrs: A dictionary mapping field names to their values in the \
        record to be inserted.

    :returns: The ID of the inserted record.
    """

    # NOTE: This should always return an ID, the `or` is for the type checker.
    return db.insert(table, list(attrs.keys()), [tuple(attrs.values())], get_last_id=True) or 0


def update_dict(db: Database, table: str, conds: dict[str, Any], attrs: dict[str, Any]):
    """
    Update some records in a database table, using dictionaries to specify the
    attributes to update and the conditions needed to update a record.

    :param db: The database.
    :param table: The table name.
    :param conds: A dictionary mapping field names to their current values to \
        determine the records to be updated. \
        Other forms of conditions are not supported by this function.
    :param attrs: A dictionary mapping field names to their updated values in \
        the record to be updated.
    """

    query_conds = map(
        lambda key, value: key + (' = ' if value is not None else ' IS ') + '%s',
        conds.keys(),
        conds.values(),
    )

    query_attrs = map(lambda key: f'{key} = %s', attrs.keys())
    query = f'UPDATE {table} SET {", ".join(query_attrs)} WHERE {" AND ".join(query_conds)}'
    db.update(query, [*attrs.values(), *conds.values()])


def delete_dict(db: Database, table: str, conds: dict[str, Any]):
    """
    Delete some records in a database table, using a dictionary to specify the
    conditions needed to update a record.

    :param db: The database.
    :param table: The table name.
    :param conds: A dictionary mapping field names to their current values to \
        determine the records to be deleted. \
        Other forms of conditions are not supported by this function.
    """

    query_conds = map(
        lambda key, value: key + (' = ' if value is not None else ' IS ') + '%s',
        conds.keys(),
        conds.values(),
    )

    query = f'DELETE FROM {table} WHERE {" AND ".join(query_conds)}'

    # NOTE: `Database.update` can be used for any query currently. Since the
    # current database abstraction is a little rudimentary, we use that here.
    db.update(query, conds.values())


def get_archive_with_study_uid(db: Database, study_uid: str):
    """
    Get the archive ID and archiving log of an existing DICOM archive in the
    database if there is one.

    :param db: The database.
    :param study_uid: The DICOM archive study uID.

    :returns: A tuple containing the archive ID and the archiving log if an \
        archive is found, or `None` otherwise.
    """

    results = select_dict(db, ['TarchiveID', 'CreateInfo'], 'tarchive', {
        'DicomArchiveID': study_uid,
    })

    if len(results) == 0:
        return None

    return results[0]['TarchiveID'], results[0]['CreateInfo']


def get_dicom_dict(log: DicomArchiveLog, summary: Summary):
    return {
        'DicomArchiveID': summary.info.study_uid,
        'PatientID': summary.info.patient.id,
        'PatientName': summary.info.patient.name,
        'PatientDoB': lib.dicom.text.write_date_none(summary.info.patient.birth_date),
        'PatientSex': summary.info.patient.sex,
        'neurodbCenterName': None,
        'CenterName': summary.info.institution or '',
        'LastUpdate': None,
        'DateAcquired': lib.dicom.text.write_date_none(summary.info.scan_date),
        'DateLastArchived': lib.dicom.text.write_datetime(datetime.now()),
        'AcquisitionCount': len(summary.acquis),
        'NonDicomFileCount': len(summary.other_files),
        'DicomFileCount': len(summary.dicom_files),
        'md5sumDicomOnly': log.tarball_md5_sum,
        'md5sumArchive': log.archive_md5_sum,
        'CreatingUser': log.creator_name,
        'sumTypeVersion': log.summary_version,
        'tarTypeVersion': log.archive_version,
        'SourceLocation': log.source_path,
        'ArchiveLocation': log.target_path,
        'ScannerManufacturer': summary.info.scanner.manufacturer,
        'ScannerModel': summary.info.scanner.model,
        'ScannerSerialNumber': summary.info.scanner.serial_number,
        'ScannerSoftwareVersion': summary.info.scanner.software_version,
        'SessionID': None,
        'uploadAttempt': 0,
        'CreateInfo': lib.dicom.dicom_log.write_to_string(log),
        'AcquisitionMetadata': lib.dicom.summary_write.write_to_string(summary),
        'DateSent': None,
        'PendingTransfer': 0,
    }


def insert(db: Database, log: DicomArchiveLog, summary: Summary):
    """
    Insert a DICOM archive into the database.

    :param db: The database.
    :param log: The archiving log of the DICOM archive.
    :param summary: The summary of the DICOM archive.
    """
    dicom_dict = get_dicom_dict(log, summary)
    dicom_dict['DateFirstArchived'] = lib.dicom.text.write_datetime(datetime.now()),
    archive_id = insert_dict(db, 'tarchive', dicom_dict)
    insert_files_series(db, archive_id, summary)


def insert_files_series(db: Database, archive_id: int, summary: Summary):
    for acqui in summary.acquis:
        insert_dict(db, 'tarchive_series', {
            'TarchiveID': archive_id,
            'SeriesNumber': acqui.series_number,
            'SeriesDescription': acqui.series_description,
            'SequenceName': acqui.sequence_name,
            'EchoTime': acqui.echo_time,
            'RepetitionTime': acqui.repetition_time,
            'InversionTime': acqui.inversion_time,
            'SliceThickness': acqui.slice_thickness,
            'PhaseEncoding': acqui.phase_encoding,
            'NumberOfFiles': acqui.number_of_files,
            'SeriesUID': acqui.series_uid,
            'Modality': acqui.modality,
        })

    for file in summary.dicom_files:
        results = select_dict(db, ['TarchiveSeriesID'], 'tarchive_series', {
            'SeriesUID': file.series_uid,
            'EchoTime': file.echo_time,
        })

        series_id = results[0]['TarchiveSeriesID']

        insert_dict(db, 'tarchive_files', {
            'TarchiveID': archive_id,
            'SeriesNumber': file.series_number,
            'FileNumber': file.file_number,
            'EchoNumber': file.echo_number,
            'SeriesDescription': file.series_description,
            'Md5Sum': file.md5_sum,
            'FileName': file.file_name,
            'TarchiveSeriesID': series_id,
        })


def update(db: Database, archive_id: int, log: DicomArchiveLog, summary: Summary):
    """
    Insert a DICOM archive into the database.

    :param db: The database.
    :param archive_id: The ID of the archive to update.
    :param log: The archiving log of the DICOM archive.
    :param summary: The summary of the DICOM archive.
    """

    # Delete the associated database DICOM files and series.
    delete_dict(db, 'tarchive_files',  {'TarchiveID': archive_id})
    delete_dict(db, 'tarchive_series', {'TarchiveID': archive_id})

    # Update the database record with the new DICOM information.
    dicom_dict = get_dicom_dict(log, summary)
    update_dict(db, 'tarchive', {'TarchiveID': archive_id}, dicom_dict)

    # Insert the new DICOM files and series.
    insert_files_series(db, archive_id, summary)
