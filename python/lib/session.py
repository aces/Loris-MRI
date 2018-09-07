"""This class gather functions for session handling."""


__license__ = "GPLv3"


class Session:
    """
    This class gather functions that interact with the database and allow session
    creation or to fetch session information directly from the database.

    :Example:

        from lib.session  import Session
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        session = Session(
            verbose, cand_id=cand_id, visit_label=visit_label, center_id=center_id
        )

        # grep session information from the database
        loris_vl_info = session.get_session_info_from_loris(db)

        # insert the session into the database
        loris_vl_info = session.create_session(db)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, verbose, cand_id, visit_label, center_id):
        """
        Constructor method for the Session class.

        :param verbose    : whether to be verbose
         :type verbose    : bool
        :param cand_id    : candidate's CandID
         :type cand_id    : int
        :param visit_label: visit label
         :type visit_label: str
        :param center_id  : center ID to associate with the session
         :type center_id  : int
        """
        self.verbose = verbose

        self.cand_id     = str(cand_id)
        self.visit_label = visit_label
        self.center_id   = center_id

    def create_session(self, db):
        """
        Creates a session using BIDS information.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """

        if self.verbose:
            print("Creating visit " + self.visit_label \
                  + " for CandID "  + self.cand_id)

        db.insert(
            table_name='session',
            column_names=('CandID', 'Visit_label', 'CenterID'),
            values=(self.cand_id, self.visit_label, str(self.center_id))
        )

        loris_session_info = self.get_session_info_from_loris(db)

        return loris_session_info

    def get_session_info_from_loris(self, db):
        """
        Grep session information from the session table using CandID and
        Visit_label.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """

        loris_session_info = db.pselect(
            "SELECT * FROM session WHERE CandID = %s AND Visit_label = %s",
            (self.cand_id, self.visit_label)
        )

        return loris_session_info[0] if loris_session_info else None
