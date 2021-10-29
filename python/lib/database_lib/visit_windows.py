"""This class performs database queries for the Visit_Windows table"""


__license__ = "GPLv3"


class VisitWindows:

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

    def check_visit_label_exits(self):
        """
        Returns a list of dictionaries storing the list of Visit_label present in the Visit_Windows table.

        :return: list of dictionaries with the list of Visit_label present in the Visit_Windows table
         :rtype: list
        """

        results = self.db.pselect(query='SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s')

        return results if results else None
