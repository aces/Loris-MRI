"""This class performs database queries for the site (mri_protocol_violated_scans) tables"""


__license__ = "GPLv3"


class MriProtocolViolatedScans:

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

        self.db.insert(
            table_name="mri_protocol_violated_scans",
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )

    def get_protocol_violations_for_tarchive_id(self, tarchive_id):

        query = "SELECT minc_location as File FROM mri_protocol_violated_scans WHERE TarchiveID = %s"

        results = self.db.pselect(query=query, args=(tarchive_id,))
        files_inserted_list = [v["File"] for v in results]

        return files_inserted_list if results else None
