"""This class performs parameter_type related database queries and common checks"""

__license__ = "GPLv3"


class ParameterType:
    """
    This class performs database queries for imaging dataset stored in the parameter_type table.

    :Example:

        from lib.parameter_type import ParameterType
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        param_type_obj = ParameterType(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the ParameterType class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """
        self.db = db
        self.verbose = verbose

    def get_parameter_type_id(self, param_name=None, param_alias=None):

        query = "SELECT ParameterTypeID FROM parameter_type WHERE "
        args = None

        if param_name:
            query += " Name = %s "
            args = (param_name,)
        elif param_alias:
            query += " Alias = %s "
            args = (param_alias,)

        results = self.db.pselect(query=query, args=args)
        return results[0]["ParameterTypeID"] if results else None

    def get_bids_to_minc_mapping_dict(self):

        query = "SELECT Name, Alias FROM parameter_type"

        results = self.db.pselect(query=query)

        bids_to_minc_mapping_dict = {}
        for row_nb in results:
            minc_param_name = row_nb['Name']
            bids_param_name = row_nb['Alias']
            bids_to_minc_mapping_dict[bids_param_name] = minc_param_name

        return bids_to_minc_mapping_dict

    def insert_parameter_type(self, field_value_dict):

        return self.db.insert(
            table_name='parameter_type',
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=True
        )