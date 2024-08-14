"""This class performs database queries for the site mri_scan_type table"""


__license__ = "GPLv3"


class MriScanType:
    """
    This class performs database queries for imaging dataset stored in the mri_scan_type table.

    :Example:

        from lib.mri_scan_type import MriScanType
        from lib.dataclass.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_scan_type_db_obj = MriScanType(db, verbose)

        ...
    """

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
        """
        Get a scan type name based on a scan type ID.

        :param scan_type_id: ID of the scan type to look up
         :type scan_type_id: int

        :return: name of the scan type queried
         :rtype: str
        """

        results = self.db.pselect(
            query='SELECT Scan_type FROM mri_scan_type WHERE ID = %s',
            args=(scan_type_id,)
        )

        return results[0]['Scan_type'] if results else None

    def get_scan_type_id_from_name(self, scan_type_name):
        """
        Get a scan type ID based on a scan type name.

        :param scan_type_name: name of the scan type to look up
         :type scan_type_name: str

        :return: ID of the scan type queried
         :rtype: int
        """

        results = self.db.pselect(
            query='SELECT ID FROM mri_scan_type WHERE Scan_type = %s',
            args=(scan_type_name,)
        )

        return results[0]['ID'] if results else None
