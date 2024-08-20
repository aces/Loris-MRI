"""This class performs database queries for the Visit_Windows table"""


__license__ = "GPLv3"


class VisitWindows:
    """
    This class performs database queries for the VisitWindows table.

    :Example:

        from lib.visit_windows import VisitWindows
        from lib.database_lib import Database

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

    def check_visit_label_exits(self, visit_label):
        """
        Returns a list of dictionaries storing the list of Visit_label present in the Visit_Windows table.

        :return: list of dictionaries with the list of Visit_label present in the Visit_Windows table
         :rtype: list
        """

        query = 'SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s'
        results = self.db.pselect(query=query, args=(visit_label,))

        return results if results else None
