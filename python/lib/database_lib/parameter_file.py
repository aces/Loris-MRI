"""This class performs parameter_file related database queries and common checks"""

__license__ = "GPLv3"


class ParameterFile:
    """
    This class performs database queries for imaging dataset stored in the parameter_file table.

    :Example:

        from lib.parameter_file import ParameterFile
        from lib.database_lib import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        param_file_obj = ParameterFile(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the ParameterFile class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """
        self.db = db
        self.verbose = verbose

    def insert_parameter_file(self, field_value_dict):
        """
        Inserts a row into the parameter_file table based on fields/values dictionary provided to the function.

        :param field_value_dict: dictionary where the parameter_file field name are keys and values to insert
                                 are in the dictionary values
         :type field_value_dict: dict
        """

        self.db.insert(
            table_name='parameter_file',
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )

    def get_parameter_file_for_file_id_param_type_id(self, file_id, param_type_id):
        """
        Get a row from parameter_file for a given FileID and ParameterTypeID

        :param file_id: FileID to use in the query
         :type file_id: int
        :param param_type_id: ParameterTypeID to use in the query
         :type param_type_id: int

        :return: dictionary with the row returned from the query
         :rtype: dict
        """

        query = "SELECT * FROM parameter_file WHERE FileID=%s AND ParameterTypeID=%s"
        results = self.db.pselect(query, (file_id, param_type_id))

        return results[0] if results else None

    def update_parameter_file(self, value, param_file_id):
        """
        Update parameter_file table Value field for a given ParameterFileID.

        :param value: value to be updated in the Value field of parameter_file
         :type value: str
        :param param_file_id: ParameterFileID to update
         :type param_file_id: int
        """

        self.db.update(
            query="UPDATE parameter_file SET Value=%s WHERE ParameterFileID=%s",
            args=(value, param_file_id)
        )
