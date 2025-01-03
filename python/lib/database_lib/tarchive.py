"""This class performs DICOM archive related database queries and common checks"""

from typing_extensions import deprecated

__license__ = "GPLv3"


@deprecated('Use `lib.db.models.dicom_archive.DbDicomArchive` instead')
class Tarchive:
    """
    This class performs database queries for DICOM archives.

    :Example:

        from lib.tarchive import Tarchive
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        tarchive = Tarchive(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the Tarchive class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    @deprecated('Use `lib.db.queries.dicom_archive.try_get_dicom_archive_with_*` instead')
    def create_tarchive_dict(self, archive_location=None, tarchive_id=None):
        """
        Create dictionary with DICOM archive information selected from the tarchive table.

        :param archive_location: relative location of the DICOM archive (without data directory path)
         :type archive_location: str
        :param tarchive_id     : TarchiveID of the DICOM archive in the tarchive table
         :type tarchive_id     : int

        :return: dictionary with the DICOM archive information selected from the tarchive table
         :rtype: dict
        """

        query = 'SELECT * FROM tarchive WHERE '
        args = None

        if archive_location:
            query += ' ArchiveLocation LIKE %s '
            args = ('%' + archive_location + '%',)
        elif tarchive_id:
            query += ' TarchiveID = %s '
            args = (tarchive_id,)

        results = self.db.pselect(query=query, args=args)

        return results[0] if results else None

    @deprecated('Use `lib.db.models.dicom_archive.DbDicomArchive` instead')
    def update_tarchive(self, tarchive_id, fields, values):
        """
        Updates the tarchive table for a given TarchiveID.

        :param tarchive_id: TarchiveID row to update in the tarchive table
         :type tarchive_id: int
        :param fields: tarchive table fields to update
         :type fields: tuple
        :param values: values to use to update the tarchive table fields
         :type values: tuple
        """

        query = "UPDATE tarchive SET "

        query += ", ".join(map(lambda x: x + " = %s", fields))

        query += " WHERE TarchiveID = %s"

        args = values + (tarchive_id,)

        self.db.update(query=query, args=args)
