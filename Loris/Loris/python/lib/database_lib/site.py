"""This class performs database queries for the site (psc) table"""


__license__ = "GPLv3"


class Site:
    """
    This class performs database queries on the psc (site) table.

    :Example:

        from lib.site import Site
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        site_db_obj = Site(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the Site class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def get_list_of_sites(self):
        """
        Returns a list of dictionaries storing the list of sites present in the psc table.

        :return: list of dictionaries with the list of sites present in the psc table
         :rtype: list
        """

        results = self.db.pselect(query='SELECT * FROM psc')

        return results if results else None
