"""This class performs database queries for the config table"""


__license__ = "GPLv3"


class Config:

    def __init__(self, db, verbose):
        """
        Constructor method for the Config class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db      = db
        self.verbose = verbose

    def get_config(self, config_name):
        """
        Grep the Value of a ConfigSettings from the Config table.

        :param config_name: name of the ConfigSettings
         :type config_name: str

        :return: the value from the Config table or None if no value found
         :rtype: str
        """

        query = "SELECT Value FROM Config WHERE ConfigID = (" \
                  "SELECT ID FROM ConfigSettings WHERE Name = %s" \
                ");"
        config_value = self.db.pselect(query, (config_name,))

        return config_value[0]['Value'] if config_value else None
