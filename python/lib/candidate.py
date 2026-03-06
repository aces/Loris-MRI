"""This class gather functions for candidate handling."""

import random

from lib.db.queries.candidate import try_get_candidate_with_cand_id
from lib.env import Env


class Candidate:
    """
    This class gather functions that interact with the database and allow candidate
    creation or to fetch candidate information directly from the database.

    :Example:

        from lib.candidate import Candidate
        from lib.database  import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        candidate = Candidate(verbose=verbose, psc_id=bids_sub_id)

        # grep the candidate info from the LORIS database
        loris_cand_info = candidate.get_candidate_info_from_loris(db)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, verbose, psc_id=None, cand_id=None, sex=None, dob=None):
        """
        Constructor method for the Candidate class.

        :param verbose: whether to be verbose
         :type verbose: bool
        :param psc_id : candidate's PSCID
         :type psc_id : str
        :param cand_id: candidate's CandID
         :type cand_id: int
        :param sex    : candidate's sex
         :type sex    : str
        :param dob    : candidate's date of birth
         :type dob    : str
        """
        self.verbose = verbose

        # create the candidate object
        self.psc_id     = psc_id
        self.cand_id    = cand_id
        self.sex        = sex
        self.dob        = dob
        self.age        = None
        self.center_id  = None
        self.project_id = None

    def get_candidate_info_from_loris(self, db):
        """
        Grep candidate information from the candidate table using the PSCID or CandID.

        :param db: database handler object
         :type db: object

        :return: dictionary with candidate info from the candidate's table
         :rtype: dict
        """

        loris_cand_info = None
        if self.cand_id:
            loris_cand_info = db.pselect(
                "SELECT * FROM candidate WHERE CandID = %s",
                (self.cand_id,),
            )
        elif self.psc_id:
            loris_cand_info = db.pselect(
                "SELECT * FROM candidate WHERE PSCID = %s",
                (self.psc_id,),
            )

        return loris_cand_info[0] if loris_cand_info else None

    @staticmethod
    def generate_cand_id(db):
        """
        Static method that generates a random CandID that does not already
        exist in the database and returns it.

        :param db: database handler object
         :type db: object

        :return: the new CandID to be used for candidate registration
         :rtype: int
        """

        id = random.randint(100000, 999999)

        while db.pselect("SELECT * FROM candidate WHERE CandID = %s", (id,)):
            # pick a new id
            id = random.randint(100000, 999999)

        return id


def generate_new_cand_id(env: Env) -> int:
    """
    Generate a new random CandID that is not already present in the database.
    """

    while True:
        cand_id = random.randint(100000, 999999)
        candidate = try_get_candidate_with_cand_id(env.db, cand_id)
        if candidate is None:
            return cand_id
