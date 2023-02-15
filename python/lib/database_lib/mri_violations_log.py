"""This class performs database queries for the mri_violations_log table"""


__license__ = "GPLv3"


class MriViolationsLog:
    """
    This class performs database queries for imaging dataset stored in the mri_violations_log table.

    :Example:

        from lib.mri_violations_log import MriViolationsLog
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_viol_log_db_obj = MriViolationsLog(db, verbose)

        ...
    """

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
        """
        Inserts a row into the `mri_violations_log` table with information present in the field_value_dict.

        :param field_value_dict: dictionary with table field as keys and values to insert as values
         :type field_value_dict: dict
        """

        self.db.insert(
            table_name="mri_violations_log",
            column_names=field_value_dict.keys(),
            values=field_value_dict.values(),
            get_last_id=False
        )

    def get_violations_for_tarchive_id(self, tarchive_id, severity=None):
        """
        Get the list of violations logged in `mri_violations_log` with excluded severity for a given `TarchiveID`.

        :param tarchive_id: `TarchiveID` to restrict the query on
         :type tarchive_id: int
        :param severity: severity of the violation (warning or exclude)
         :type severity: str

        :return: list of files inserted into the `mri_violations_log` table
         :rtype: list
        """

        query = "SELECT * FROM mri_violations_log WHERE TarchiveID = %s"
        args = (tarchive_id,)

        if severity:
            query += " AND Severity = %s"
            args += (severity,)

        return self.db.pselect(query=query, args=args)

    def update_violations_log(self, log_id, fields, values):
        """
        Inserts into the `mri_violations_log` table a new row with file information.

        :param log_id: ID of the file to update in the `mri_violations_log` table
         :type log_id: int
        :param fields: tuple with the list of fields to update in the `mri_violations_log` table
         :type fields: tuple
        :param values: tuple with the list of values to use to update the `mri_violations_log` table
         :type values: tuple
        """

        query = 'UPDATE mri_violations_log SET '

        query += ', '.join(map(lambda x: x + ' = %s', fields))

        query += ' WHERE LogID = %s'

        args = values + (log_id,)

        self.db.update(query=query, args=args)
