"""This class performs database queries for the mri_protocol_violated_scans table"""


__license__ = "GPLv3"


class MriProtocolViolatedScans:
    """
    This class performs database queries for imaging dataset stored in the mri_protocol_violated_scans table.

    :Example:

        from lib.mri_protocol_violated_scans import MriProtocolViolatedScans
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_prot_viol_scans_db_obj = MriProtocolViolatedScans(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the MriProtocolViolatedScans class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def insert_protocol_violated_scans(self, field_value_dict):
        """
        Inserts a row into the mri_protocol_violated_scans table with information present in the field_value_dict.

        :param field_value_dict: dictionary with table field as keys and values to insert as values
         :type field_value_dict: dict
        """

        self.db.insert(
            table_name="mri_protocol_violated_scans",
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )

    def get_protocol_violations_for_tarchive_id(self, tarchive_id):
        """
        Get the list of protocol violations logged for a given `TarchiveID`.

        :param tarchive_id: `TarchiveID` to restrict the query on
         :type tarchive_id: int

        :return: list of files inserted into the `mri_protocol_violated_scans` table
         :rtype: list
        """

        query = "SELECT minc_location as File FROM mri_protocol_violated_scans WHERE TarchiveID = %s"

        results = self.db.pselect(query=query, args=(tarchive_id,))
        files_inserted_list = [v["File"] for v in results]

        return files_inserted_list if results else None
