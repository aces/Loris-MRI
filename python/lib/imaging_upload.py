"""This class gather functions for mri upload handling."""

from lib.database_lib.mri_upload_db import MriUploadDB

__license__ = "GPLv3"


class ImagingUpload:
    """
    This class gather functions that interact with the database and allow mri_upload
    updates or to fetch mri_upload information directly from the database.

    :Example:

        from lib.imaging_upload  import ImagingUpload
        from lib.dataclass.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        imaging_upload_obj = ImagingUpload(db, verbose)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the MriUpload class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose
        self.mri_upload_db_obj = MriUploadDB(db, verbose)

        self.imaging_upload_dict = dict()

    def create_imaging_upload_dict_from_upload_id(self, upload_id):
        """
        Fill in the imaging upload dictionary with the information found for a given upload ID in the mri_upload table.

        :param upload_id: UploadID to use to query mri_upload
         :type upload_id: str
        """

        results = self.mri_upload_db_obj.create_mri_upload_dict('UploadID', upload_id)
        self.imaging_upload_dict = results[0] if results else None

    def create_imaging_upload_dict_from_tarchive_id(self, tarchive_id):
        """
        Fill in the imaging upload dictionary with information found for a given TarchiveID in the mri_upload table.

        :param tarchive_id: TarchiveID to use to query mri_upload
         :type tarchive_id: str

        :return: message if 0 row or more than one row were found in the mri_upload table for the given Tarchive
         :rtype: bool, str
        """

        results = self.mri_upload_db_obj.create_mri_upload_dict('TarchiveID', tarchive_id)

        if len(results) > 1:
            return False, f"Found {len(results)} rows in mri_upload for 'TarchiveID' {tarchive_id}"
        elif len(results) == 1:
            self.imaging_upload_dict = results[0]
            return True, None
        else:
            return False, f"Did not find an entry in mri_upload associated with 'TarchiveID' {tarchive_id}"

    def update_mri_upload(self, upload_id, fields, values):
        """
        Calls the MriUpload database lib to update the mri_upload table.

        :param upload_id: UploadID to update
         :type upload_id: int
        :param fields: Fields that need to be updated in the mri_upload table
         :type fields: tuple
        :param fields: Values to use to update the fields that need to be updated in the mri_upload table
         :type fields: tuple
        """

        self.mri_upload_db_obj.update_mri_upload(upload_id, fields, values)
