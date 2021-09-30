"""This class performs session table related database queries and common checks"""


__license__ = "GPLv3"


class SessionDB:
    """
    This class performs database queries for session table.

    :Example:

        from lib.database_lib.session_db import SessionDB
        from lib.database import Database

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

        query = "SELECT * FROM session" \
                " JOIN psc USING (CenterID)" \
                " WHERE CandID=%s AND LOWER(Visit_label)=LOWER(%s) AND Active='Y'"
        results = self.db.pselect(query=query, args=(cand_id, visit_label))

        return results[0] if results else None

    def get_session_center_info(self, pscid, visit_label):

        query = "SELECT * FROM session" \
                " JOIN psc USING (CenterID)" \
                " JOIN candidate USING (CandID)" \
                " WHERE PSCID=%s AND Visit_label=%s"
        results = self.db.pselect(query=query, args=(pscid, visit_label))

        if results:
            return results[0]

    def determine_next_session_site_id_and_visit_number(self, cand_id):

        query = "SELECT IFNULL(MAX(VisitNo), 0) + 1 AS newVisitNo, CenterID" \
                " FROM session WHERE CandID = %s GROUP BY CandID, CenterID"
        results = self.db.pselect(query=query, args=(cand_id,))

        if results:
            return results[0]

        query = "SELECT 1 AS newVisitNo, RegistrationCenterID AS CenterID" \
                " FROM candidate WHERE CandID = %s"
        results = self.db.pselect(query=query, args=(cand_id,))

        if results:
            return results[0]

    def insert_into_session(self, fields, values):

        session_id = self.db.insert(
            table_name="session",
            column_names=fields,
            values=values,
            get_last_id=True
        )

        return session_id
