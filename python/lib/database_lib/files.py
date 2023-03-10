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

    def find_file_with_series_uid_and_echo_time(self, series_uid, echo_time, phase_enc_dir, echo_number):
        """
        Select files stored in the `files` table with a given `SeriesUID` and `EchoTime`.

        :param series_uid: SeriesUID of the file to look for in the files table
         :type series_uid: str
        :param echo_time: Echo Time of the file to look for in the files table
         :type echo_time: float
        :param phase_enc_dir: Phase Encoding Direction of the file to look for
         :type phase_enc_dir: str
        :param echo_number: Echo Number of the file to look for
         :type echo_number: int

        :return: entry from the `files` table for the file with SeriesUID and EchoTime
         :rtype: dict
        """

        query = "SELECT * FROM files WHERE SeriesUID = %s  AND EchoTime = %s "
        args = [series_uid, echo_time]

        if phase_enc_dir:
            query += " AND PhaseEncodingDirection = %s "
            args.append(phase_enc_dir)
        else:
            query += " AND PhaseEncodingDirection IS NULL "

        if echo_number:
            query += " AND EchoNumber = %s "
            args.append(echo_number)
        else:
            query += " AND EchoNumber IS NULL "

        results = self.db.pselect(
            query=query,
            args=tuple(args)
        )

        return results[0] if results else None

    def find_file_with_hash(self, file_hash):
        """
        Select files stored in the `files` table with a given hash stored in `parameter_file`.

        :param file_hash: hash of the file to look for in the `files` table
         :type file_hash: str

        :return: entry from the `files` table for the file with the provided hash
         :rtype: dict
        """

        param_type_obj = ParameterType(self.db, self.verbose)
        blake2b_param_type_id = param_type_obj.get_parameter_type_id(param_name="file_blake2b_hash")
        md5_param_type_id = param_type_obj.get_parameter_type_id(param_name="md5hash")

        query = "SELECT * FROM files" \
                " JOIN parameter_file USING(FileID)" \
                " WHERE ParameterTypeID IN (%s, %s) AND Value = %s"

        results = self.db.pselect(query=query, args=(blake2b_param_type_id, md5_param_type_id, file_hash))

        return results[0] if results else None

    def insert_files(self, field_value_dict):
        """
        Inserts into the `files` table a new row with file information.

        :param field_value_dict: dictionary with column names as keys and values to insert as values
         :type field_value_dict: dict

        :return: FileID of the registered file or None if the insert was not successful
         :rtype: int
        """

        return self.db.insert(
            table_name='files',
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=True
        )

    def update_files(self, file_id, fields, values):
        """
        Inserts into the `files` table a new row with file information.

        :param file_id: FileID of the file to update in the `files` table
         :type file_id: int
        :param fields: tuple with the list of fields to update in the `files` table
         :type fields: tuple
        :param values: tuple with the list of values to use to update the `files` table
         :type values: tuple
        """

        query = 'UPDATE files SET '

        query += ', '.join(map(lambda x: x + ' = %s', fields))

        query += ' WHERE FileID = %s'

        args = values + (file_id,)

        self.db.update(query=query, args=args)

    def select_distinct_acquisition_protocol_id_per_tarchive_source(self, tarchive_id):
        """
        Get a list of distinct scan types (a.k.a. `AcquisitionProtocolID`) inserted into the `files`
        table for a given DICOM archive (a.k.a. `TarchiveSource`).

        :param tarchive_id: `TarchiveID` to use as the `TarchiveSource` to restrict the SELECT statement on
         :type tarchive_id: int

        :return: list of scan types found (`AcquisitionProtocolID`)
         :rtype: list
        """

        query = "SELECT DISTINCT AcquisitionProtocolID FROM files WHERE TarchiveSource = %s"

        results = self.db.pselect(query=query, args=(tarchive_id,))
        acquisition_protocol_id_list = [v["AcquisitionProtocolID"] for v in results]

        return acquisition_protocol_id_list

    def get_file_ids_and_series_number_per_scan_type_and_tarchive_id(self, tarchive_id, scan_type_id):
        """
        Get the list of `FileID` and `SeriesNumber` for the files inserted into the `files` table
        associated to a given `TarchiveID`.

        :param tarchive_id: `TarchiveID` to restrict the query on
         :type tarchive_id: int
        :param scan_type_id: ID of the scan type to restrict the query on
         :type scan_type_id: int

        :return: list of `FileID` and `SeriesNumber` for a given `TarchiveID` and `AcquisitionProtocolID`
         :rtype: list
        """

        query = "SELECT FileID, Value AS SeriesNumber " \
                "FROM files " \
                "  JOIN parameter_file USING(FileID) " \
                "  JOIN parameter_type USING(ParameterTypeID) " \
                "WHERE TarchiveSource = %s AND AcquisitionProtocolID = %s AND Name = %s"

        return self.db.pselect(query=query, args=(tarchive_id, scan_type_id, "series_number"))

    def get_files_inserted_for_tarchive_id(self, tarchive_id):
        """
        Get the list of files that were inserted into the `files` table for a given `TarchiveID`.

        :param tarchive_id: `TarchiveID` to restrict the query on
         :type tarchive_id: int

        :return: list of relative file path present in the `files` table associated to the `TarchiveID`
         :rtype: list
        """

        query = "SELECT * FROM files WHERE TarchiveSource = %s"

        return self.db.pselect(query=query, args=(tarchive_id,))

    def get_files_inserted_for_session_id(self, session_id):
        """
        Get the list of files that were inserted into the `files` table for a given `TarchiveID`.

        :param session_id: `SessionID` to restrict the query on
         :type session_id: int

        :return: list of relative file path present in the `files` table associated to the `SessionID`
         :rtype: list
        """

        query = "SELECT * FROM files WHERE SessionID = %s"

        return self.db.pselect(query=query, args=(session_id,))
