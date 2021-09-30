"""This class gather functions for mri upload handling."""

from lib.database_lib.mri_upload_db import MriUploadDB

__license__ = "GPLv3"


class ImagingUpload:
    """
    This class gather functions that interact with the database and allow session
    creation or to fetch session information directly from the database.

    :Example:

        from lib.imaging_upload  import ImagingUpload
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_upload_obj = MriUpload(db, verbose)

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

        results = self.mri_upload_db_obj.create_mri_upload_dict('UploadID', upload_id)
        self.imaging_upload_dict = results[0]

    def create_imaging_upload_dict_from_tarchive_id(self, tarchive_id):

        results = self.mri_upload_db_obj.create_mri_upload_dict('TarchiveID', tarchive_id)

        if len(results) > 1:
            return False, f"Found {len(results)} rows in mri_upload for 'TarchiveID' {tarchive_id}"
        elif len(results) == 1:
            self.imaging_upload_dict = results[0]
            return True, None
        else:
            return False, f"Did not find an entry in mri_upload associated with 'TarchiveID' {tarchive_id}"

    def update_mri_upload(self, upload_id, fields, values):

        self.mri_upload_db_obj.update_mri_upload(upload_id, fields, values)
