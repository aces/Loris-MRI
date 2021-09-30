"""This class gather functions for DICOM archive handling."""

from lib.database_lib.tarchive import Tarchive
from lib.database_lib.tarchive_series import TarchiveSeries

__license__ = "GPLv3"


class DicomArchive:
    """
    This class gather functions that interact with the database and allow session
    creation or to fetch DICOM archive information directly from the database.

    :Example:

        from lib.database import Database
        from lib.dicom_archive import DicomArchive

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        dicom_archive_obj = DicomArchive(db, verbose)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the DicomArchive class.

        :param db: Database class object
         :type db: object
        :param verbose: whether to be verbose
         :type verbose: bool
        """
        self.db = db
        self.verbose = verbose

        self.tarchive_db_obj = Tarchive(db, verbose)
        self.tarchive_series_db_obj = TarchiveSeries(db, verbose)

        self.tarchive_info_dict = dict()

    def populate_tarchive_info_dict_from_archive_location(self, archive_location):

        self.tarchive_db_obj.create_tarchive_dict(archive_location=archive_location)

    def populate_tarchive_info_dict_from_tarchive_id(self, tarchive_id):

        self.tarchive_db_obj.create_tarchive_dict(tarchive_id=tarchive_id)
