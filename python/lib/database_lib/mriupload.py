"""This class performs database queries for the mri_upload table"""

import datetime

__license__ = "GPLv3"


class MriUpload:

    def __init__(self, db, verbose):
        """
        Constructor method for the MriUplaod class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.verbose = verbose
        self.mri_upload_dict = dict()

    def update_mri_upload(self, upload_id, fields, values):
        """
        Update the isTarchiveValidated field of the upload with the value provided
        to the function.

        :param upload_id: UploadID associated to the upload
         :type upload_id: int
        :param fields   : list with fields to be updated in the mri_upload table
         :type fields   : tuple
        :param values   : list of values to use for the update query
         :type values   : tuple
        """

        query = 'UPDATE mri_upload SET '

        query += ', '.join(map(lambda x: x + ' = %s', fields))

        query += ' WHERE UploadID = %s'

        args = values + (upload_id,)

        self.db.update(query=query, args=args)

    def create_mri_upload_dict(self, where_field, where_value):

        query = "SELECT * FROM mri_upload"

        if where_field == "UploadID":
            query += " WHERE UploadID = %s"
        elif where_field == "TarchiveID":
            query += " WHERE TarchiveID = %s"
        elif where_field == "SessionID":
            query += " WHERE SessionID = %s"
        results = self.db.pselect(query, (where_value,))

        if len(results) > 1:
            error_msg = f"Found {len(results)} rows in mri_upload for {where_field} {where_value}"
            return False, error_msg
        elif len(results) == 1:
            self.mri_upload_dict = results[0]
            return True, None
        else:
            error_msg = f"Did not find an entry in mri_upload associated with {where_field} {where_value}"
            return False, error_msg
