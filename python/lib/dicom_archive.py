"""This class gather functions for DICOM archive handling."""

import lib.utilities as utilities
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
        self.tar_series_db_obj = TarchiveSeries(db, verbose)

        self.tarchive_info_dict = dict()

    def populate_tarchive_info_dict_from_archive_location(self, archive_location):
        """
        Populate the DICOM archive information dictionary (self.tarchive_info_dict) with information found in
        the tarchive table for a given archive location.

        :param archive_location: location of the DICOM archive (relative path)
         :type archive_location: str
        """
        self.tarchive_db_obj.create_tarchive_dict(archive_location=archive_location)

    def populate_tarchive_info_dict_from_tarchive_id(self, tarchive_id):
        """
        Populate the DICOM archive information dictionary (self.tarchive_info_dict) with information found in
        the tarchive table for a given TarchiveID.

        :param tarchive_id: TarchiveID of the DICOM archive
         :type tarchive_id: int
        """
        self.tarchive_db_obj.create_tarchive_dict(tarchive_id=tarchive_id)

    def populate_tarchive_info_dict_from_series_uid_and_echo_time(self, series_uid, echo_time):
        """
        Populate the DICOM archive information dictionary (self.tarchive_info_dict) with information found in
        the tarchive table for a given TarchiveID.

        :param series_uid: SeriesUID to use to find entries in the tarchive_series table
         :type series_uid: str
        :param echo_time: Echo time to use to find entries in the tarchive_series table
         :type echo_time: float
        """
        tarchive_series_info_dict = self.tar_series_db_obj.get_tarchive_series_from_series_uid_and_echo_time(
            series_uid, echo_time
        )

        if "TarchiveID" in tarchive_series_info_dict.keys():
            tarchive_id = tarchive_series_info_dict["TarchiveID"]
            return self.populate_tarchive_info_dict_from_tarchive_id(tarchive_id=tarchive_id)

    def validate_dicom_archive_md5sum(self, tarchive_path):
        """
        This function validates that the md5sum of the DICOM archive on the filesystem is the same
        as the md5sum of the registered entry in the tarchive table.

        :param tarchive_path: path to the DICOM archive to be validated against the database
         :type tarchive_path: str

        :return result: dictionary with the result of the validation
         :rtype result: dict
        """

        # compute the md5sum of the tarchive file
        tarchive_file_md5sum = utilities.compute_md5sum(tarchive_path)

        # grep the md5sum stored in the database
        tarchive_db_md5sum = self.tarchive_info_dict['md5sumArchive'].split()[0]

        # check that the two md5sum are the same
        result = dict()
        if tarchive_db_md5sum == tarchive_file_md5sum:
            result['success'] = True
            result['message'] = f"checksum for target: {tarchive_file_md5sum}; " \
                                f"checksum from database: {tarchive_db_md5sum}"
        else:
            result['success'] = False
            result['message'] = "ERROR: DICOM archive seems corrupted or modified. Upload will exit now."

        return result
