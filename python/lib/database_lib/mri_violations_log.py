"""This class performs database queries for the site (mri_violations_log) tables"""


__license__ = "GPLv3"


class MriViolationsLog:

    def __init__(self, db, verbose):
        """
        Constructor method for the MriViolationsLog class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def insert_violations_log(self, field_value_dict):

        self.db.insert(
            table_name="mri_violations_log",
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )
