"""This class performs candidate table related database queries and common checks"""

from typing_extensions import deprecated

__license__ = "GPLv3"


@deprecated('Use `lib.db.model.candidate.DbCandidate` instead')
class CandidateDB:
    """
    This class performs database queries for candidate table.

    :Example:

        from lib.database_lib.candidate_db import CandidateDB
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        candidate_db_obj = CandidateDB(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the CandidateDB class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    @deprecated('Use `lib.db.query.candidate.try_get_candidate_with_cand_id` instead')
    def get_candidate_psc_id(self, cand_id: int) -> str | None:
        """
        Return a candidate PSCID and based on its CandID, or `None` if no candidate is found in
        the database.
        """

        query = 'SELECT PSCID FROM candidate WHERE CandID = %s'

        results = self.db.pselect(query, args=(cand_id,))

        return results[0]['PSCID'] if results else None
