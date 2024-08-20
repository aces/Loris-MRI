"""This class performs session table related database queries and common checks"""


__license__ = "GPLv3"


class SessionDB:
    """
    This class performs database queries for session table.

    :Example:

        from lib.database_lib.session_db import SessionDB
        from lib.database_mysqldb import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        session_obj = SessionDB(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the SessionDB class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def create_session_dict(self, cand_id, visit_label):
        """
        Queries the session table for a particular candidate ID and visit label and returns a dictionary
        with the session information.

        :param cand_id: CandID
         :type cand_id: int
        :param visit_label: Visit label of the session
         :type visit_label: str

        :return: dictionary of the information present in the session table for that candidate/visit
         :rtype: dict
        """

        query = "SELECT * FROM session" \
                " JOIN psc USING (CenterID)" \
                " WHERE CandID=%s AND LOWER(Visit_label)=LOWER(%s) AND Active='Y'"
        results = self.db.pselect(query=query, args=(cand_id, visit_label))

        return results[0] if results else None

    def get_session_center_info(self, pscid, visit_label):
        """
        Get site information for a given visit.

        :param pscid: candidate site ID (PSCID)
         :type pscid: str
        :param visit_label: visit label
         :type visit_label: str

        :return: dictionary of site information for the visit/candidate queried
         :rtype: dict
        """

        query = "SELECT * FROM session" \
                " JOIN psc USING (CenterID)" \
                " JOIN candidate USING (CandID)" \
                " WHERE PSCID=%s AND Visit_label=%s"
        results = self.db.pselect(query=query, args=(pscid, visit_label))

        return results[0] if results else None

    def determine_next_session_site_id_and_visit_number(self, cand_id):
        """
        Determines the next session site and visit number based on the last session inserted for a given candidate.

        :param cand_id: candidate ID
         :type cand_id: int

        :return: a dictionary with 'newVisitNo' and 'CenterID' keys/values
         :rtype: dict
        """
        query = "SELECT IFNULL(MAX(VisitNo), 0) + 1 AS newVisitNo, CenterID" \
                " FROM session WHERE CandID = %s GROUP BY CandID, CenterID"
        results = self.db.pselect(query=query, args=(cand_id,))

        if results:
            return results[0]

        query = "SELECT 1 AS newVisitNo, RegistrationCenterID AS CenterID FROM candidate WHERE CandID = %s"
        results = self.db.pselect(query=query, args=(cand_id,))

        return results[0] if results else None

    def insert_into_session(self, fields, values):
        """
        Insert a new row in the session table using fields list as column names and values as values.

        :param fields: column names of the fields to use for insertion
         :type fields: list
        :param values: values for the fields to insert
         :type values: list

        :return: ID of the new session registered
         :rtype: int
        """

        session_id = self.db.insert(
            table_name="session",
            column_names=fields,
            values=values,
            get_last_id=True
        )

        return session_id
