"""This class performs tarchive_series related database queries and common checks"""

from typing_extensions import deprecated

__license__ = "GPLv3"


@deprecated('Use `lib.db.models.dicom_archive_series.DbDicomArchiveSeries` instead')
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

    @deprecated('Use `lib.db.queries.dicom_archive.try_get_dicom_archive_series_with_series_uid_echo_time` instead')
    def get_tarchive_series_from_series_uid_and_echo_time(self, series_uid, echo_time):
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

        return results[0] if results else None
