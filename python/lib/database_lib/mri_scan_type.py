"""This class performs database queries for the site mri_scan_type table"""


__license__ = "GPLv3"


class MriScanType:

    def __init__(self, db, verbose):
        """
        Constructor method for the MriScanType class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def get_scan_type_name_from_id(self, scan_type_id):

        results = self.db.pselect(
            query='SELECT Scan_type FROM mri_scan_type WHERE ID = %s',
            args=(scan_type_id,)
        )

        return results[0]['Scan_type'] if results else None
