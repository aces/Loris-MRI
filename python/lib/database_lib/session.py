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

        tarchive = Session(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the TarchiveSeries class.

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

        query = f"SELECT ID, ProjectID, SubprojectID, CandID, Visit_label FROM session" \
                f" WHERE CandID=%s AND LOWER(Visit_label)=LOWER(%s) AND Active='Y'"
        results = self.db.pselect(query=query, args=(cand_id, visit_label))

        if results:
            self.session_info_dict = results[0]