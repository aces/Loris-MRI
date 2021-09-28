"""This class performs files/param_file related database queries and common checks"""

from lib.database_lib.parameter_type import ParameterType

__license__ = "GPLv3"


class Files:
    """
    This class performs database queries for imaging dataset stored in the files tables (MRI, PET...).

    :Example:

        from lib.files import Files
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        files_obj = Files(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the Tarchive class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """
        self.db = db
        self.verbose = verbose

    def find_file_with_series_uid_and_echo_time(self, series_uid, echo_time):

        query = "SELECT * FROM files WHERE SeriesUID = %s and EchoTime = %s "
        results = self.db.pselect(query=query, args=(series_uid, echo_time))

        # save the result in self.files_info_dict and return True if a row was found
        # return False if no row found for the archive location or tarchiveID in the tarchive table
        return results[0] if results else None

    def find_file_with_hash(self, file_hash):

        param_type_obj = ParameterType(self.db, self.verbose)
        blake2b_param_type_id = param_type_obj.get_parameter_type_id(param_name="file_blake2b_hash")
        md5_param_type_id = param_type_obj.get_parameter_type_id(param_name="md5hash")

        query = "SELECT * FROM files" \
                " JOIN parameter_file USING(FileID)" \
                " WHERE ParameterTypeID IN (%s, %s) AND Value = %s"

        results = self.db.pselect(query=query, args=(blake2b_param_type_id, md5_param_type_id, file_hash))

        return results[0] if results else None

    def insert_files(self, field_value_dict):

        return self.db.insert(
            table_name='files',
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=True
        )