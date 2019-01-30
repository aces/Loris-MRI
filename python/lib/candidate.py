"""This class gather functions for candidate handling."""

import random
from dateutil.parser import parse
import lib.exitcode


__license__ = "GPLv3"


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
        self.psc_id    = psc_id
        self.cand_id   = cand_id
        self.sex       = sex
        self.dob       = dob
        self.age       = None
        self.site      = None
        self.center_id = None

    def create_candidate(self, db, participants_info):
        """
        Creates a candidate using BIDS information provided in the
        participants_info's list.

        :param db               : database handler object
         :type db               : object
        :param participants_info: list of dictionary with participants
                                  information from BIDS
         :type participants_info: list

        :return: dictionary with candidate info from the candidate's table
         :rtype: dict
        """

        self.cand_id = self.generate_cand_id(db)

        for row in participants_info:
            if not row['participant_id'] == self.psc_id:
                continue
            self.grep_bids_dob(row)
            if 'sex' in row:
                self.map_sex(row['sex'])
            if 'age' in row:
                self.age = row['age']
            if 'site' in row:
                self.site = row['site']

            if self.site:
                site_info = db.pselect(
                    "SELECT CenterID FROM psc WHERE Alias = %s",
                    [self.site,]
                )
                self.center_id = site_info[0]['CenterID']
            else:
                db_sites = db.pselect("SELECT CenterID, Alias FROM psc")
                for site in db_sites:
                    if site['Alias'] in row['participant_id']:
                        self.site = site['Alias']
                        self.center_id = site['CenterID']

        if not self.center_id:
            print("ERROR: could not determine site for " + self.psc_id + "." + \
                  " Please check that your psc table contains a site with an" \
                  " Alias matching the BIDS ID or the site mentioned in" \
                  " participants.tsv's site column")
            sys.exit(lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE)

        if self.verbose:
            print("Creating candidate with " + \
                  " PSCID = "    + self.psc_id + "," + \
                  " CandID = "   + str(self.cand_id) + \
                  " and Site = " + str(self.site))

        insert_col = ('PSCID', 'CandID', 'CenterID')
        insert_val = (self.psc_id, str(self.cand_id), str(self.center_id))

        if self.sex:
            insert_col = insert_col + ('Gender',)
            insert_val = insert_val + (self.sex,)
        if self.dob:
            insert_col = insert_col + ('DoB',)
            insert_val = insert_val + (self.dob,)

        db.insert(
            table_name='candidate',
            column_names=insert_col,
            values=insert_val
        )

        loris_cand_info = self.get_candidate_info_from_loris(db)

        return loris_cand_info

    def get_candidate_info_from_loris(self, db):
        """
        Grep candidate information from the candidate table using PSCID.

        :param db: database handler object
         :type db: object

        :return: dictionary with candidate info from the candidate's table
         :rtype: dict
        """

        loris_cand_info = db.pselect(
            "SELECT * FROM candidate WHERE PSCID = %s",
            (self.psc_id,),
        )

        return loris_cand_info[0] if loris_cand_info else None

    def map_sex(self, sex):
        """
        Maps the different possible values for sex to 'Male' and 'Female' as
        present in the candidate table.

        :param sex: sex value to map to values supported in the candidate table
         :type sex: str
        """

        if sex.lower() in ('m', 'male'):
            self.sex = 'Male'

        if sex.lower() in ('f', 'female'):
            self.sex = 'Female'

    def grep_bids_dob(self, subject_info):
        """
        Greps the date of birth from the BIDS structure and add it to self.dob which
        will be inserted into the DoB field of the candidate table

        :param subject_info: dictionary with all information present in the BIDS
                             participants.tsv file for a given candidate
         :type subject_info: dict
        """

        dob_names = ['date_of_birth', 'birth_date', 'dob']
        for name in dob_names:
            if name in subject_info:
                dob   = parse(subject_info[name])
                self.dob = dob.strftime('%Y-%m-%d')

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

        while(db.pselect("SELECT * FROM candidate WHERE CandID = %s", (id,))):
            # pick a new id
            id = random.randint(100000, 999999)

        return id
