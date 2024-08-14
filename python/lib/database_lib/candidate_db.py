"""This class performs candidate table related database queries and common checks"""


__license__ = "GPLv3"


class CandidateDB:
    """
    This class performs database queries for candidate table.

    :Example:

        from lib.database_lib.candidate_db import CandidateDB
        from lib.dataclass.database import Database

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

    def check_candid_pscid_combination(self, psc_id, cand_id):
        """
        Checks whether the PSCID/CandID combination corresponds to a valid candidate in the `candidate` table.

        :param psc_id: PSCID of the candidate
         :type psc_id: str
        :param cand_id: CandID of the candidate
         :type cand_id: int

        :returns: the valid CandID and PSCID if the combination corresponds to a candidate, None otherwise
        """

        query = "SELECT c1.CandID, c2.PSCID AS PSCID " \
                " FROM candidate c1 " \
                " LEFT JOIN candidate c2 ON (c1.CandID=c2.CandID AND c2.PSCID = %s) " \
                " WHERE c1.CandID = %s"

        results = self.db.pselect(query=query, args=(psc_id, cand_id))

        return results if results else None
