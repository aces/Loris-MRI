"""This class performs database queries for the config table"""


__license__ = "GPLv3"


class Config:
    """
    This class performs database queries for the Config* tables.

    :Example:

        from lib.database_lib.config import Config
        from lib.database_lib import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        config_db_obj = Config(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the Config class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def get_config(self, config_name):
        """
        Grep the Value of a ConfigSettings from the Config table.

        :param config_name: name of the ConfigSettings
         :type config_name: str

        :return: the value from the Config table if only one value found, list with values found in the Config table
                 if multiple values found or None if no value found
         :rtype: str or list
        """

        query = "SELECT Value FROM Config WHERE ConfigID = (SELECT ID FROM ConfigSettings WHERE Name = %s)"
        results = self.db.pselect(query, (config_name,))

        if not results:
            return None
        elif len(results) == 1:
            return results[0]["Value"]
        else:
            values = [v["Value"] for v in results]
            return values
