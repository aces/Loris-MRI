"""This class performs tarchive_series related database queries and common checks"""


__license__ = "GPLv3"


class TarchiveSeries:
    """
    This class performs database queries for tarchive_series table.

    :Example:

        from lib.tarchive_series import TarchiveSeries
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        tarchive = TarchiveSeries(db, verbose)

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
        self.tarchive_series_info_dict = dict()

    def create_tarchive_series_dict_from_series_uid_and_echo_time(self, series_uid, echo_time):
        """
        Create dictionary with DICOM archive information selected from the tarchive table.

        :param series_uid: SeriesUID field to restrict the search on
         :type series_uid: str
        :param echo_time: EchoTime field to restrict the search on
         :type echo_time: float

        :return: dictionary with the tarchive series information selected from the tarchive table
         :rtype: dict
        """

        query = "SELECT * FROM tarchive_series WHERE SeriesUID = %s AND EchoTime = %s"
        results = self.db.pselect(query=query, args=(series_uid, echo_time))

        # save the result in self.tarchive_info_dict and return True if a row was found
        # return False if no row found for the archive location or tarchiveID in the tarchive table
        if results:
            self.tarchive_series_info_dict = results[0]
