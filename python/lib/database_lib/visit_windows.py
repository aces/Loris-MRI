"""This class performs database queries for the Visit_Windows table"""


__license__ = "GPLv3"


class VisitWindows:
    """
    This class performs database queries for the VisitWindows table.

    :Example:

        from lib.visit_windows import VisitWindows
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        visit_windows_db_obj = VisitWindows(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the VisitWindows class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def check_visit_label_exists(self, visit_label: str) -> bool:
        """
        Check if a visit label exists in the Visit_Windows database table.
        """

        query = 'SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s'
        results = self.db.pselect(query=query, args=(visit_label,))
        return bool(results)
