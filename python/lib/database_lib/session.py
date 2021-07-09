"""This class performs session table related database queries and common checks"""


__license__ = "GPLv3"


class Session:
    """
    This class performs database queries for session table.

    :Example:

        from lib.database_lib.session import Session
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        session_obj = Session(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the Session class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

        # this will contain the tarchive info
        self.session_info_dict = dict()

    def create_session_dict(self, cand_id, visit_label):

        query = f"SELECT * FROM session" \
                f" JOIN psc USING (CenterID)" \
                f" WHERE CandID=%s AND LOWER(Visit_label)=LOWER(%s) AND Active='Y'"
        results = self.db.pselect(query=query, args=(cand_id, visit_label))

        if results:
            self.session_info_dict = results[0]

    def get_session_center_info(self, pscid, visit_label):

        query = f"SELECT * FROM session" \
                f" JOIN psc USING (CenterID)" \
                f" JOIN candidate USING (CandID)" \
                f" WHERE PSCID=%s AND Visit_label=%s"
        results = self.db.pselect(query=query, args=(pscid, visit_label))

        if results:
            return results[0]

    def determine_next_session_site_id_and_visit_number(self, cand_id):

        query = f"SELECT IFNULL(MAX(VisitNo), 0) + 1 AS newVisitNo, CenterID" \
                f" FROM session WHERE CandID = %s GROUP BY CandID, CenterID"
        results = self.db.pselect(query=query, args=(cand_id,))

        if results:
            return results[0]

        query = f"SELECT 1 AS newVisitNo, RegistrationCenterID AS CenterID" \
                f" FROM candidate WHERE CandID = %s"
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
