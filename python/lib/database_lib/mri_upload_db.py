"""This class performs database queries for the mri_upload table"""

__license__ = "GPLv3"


class MriUploadDB:
    """
    This class performs database queries for imaging dataset stored in the mri_upload table.

    :Example:

        from lib.mri_upload import MriUploadDB
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_upload_db_obj = MriUploadDB(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the MriUplaodDB class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.verbose = verbose

    def update_mri_upload(self, upload_id, fields, values):
        """
        Update the `isTarchiveValidated` field of the upload with the value provided
        to the function.

        :param upload_id: `UploadID` associated to the upload
         :type upload_id: int
        :param fields   : list with fields to be updated in the `mri_upload` table
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
        """
        Create a dictionary out of the entry available in the `mri_upload` table.

        :param where_field: name of the field to query
         :type where_field: str
        :param where_value: field value to use to query the `mri_upload` table
         :type where_value: str

        :return: list of mri_upload found
         :rtype: list
        """

        query = "SELECT * FROM mri_upload"

        if where_field == "UploadID":
            query += " WHERE UploadID = %s"
        elif where_field == "TarchiveID":
            query += " WHERE TarchiveID = %s"
        elif where_field == "SessionID":
            query += " WHERE SessionID = %s"
        results = self.db.pselect(query, (where_value,))

        return results if results else None
