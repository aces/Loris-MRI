"""This class performs database queries for the MRICandidateErrors table"""


__license__ = "GPLv3"


class MriCandidateErrors:
    """
    This class performs database queries for imaging dataset stored in the MRICandidateErrors table.

    :Example:

        from lib.mri_candidate_errors import MriCandidateErrors
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_cand_error_db_obj = MriCandidateErrors(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the MRICandidateErrors class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def insert_mri_candidate_errors(self, field_value_dict):
        """
        Inserts a row into the MRICandidateErrors table with information present in the field_value_dict.

        :param field_value_dict: dictionary with table field as keys and values to insert as values
         :type field_value_dict: dict
        """

        self.db.insert(
            table_name="MRICandidateErrors",
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )
