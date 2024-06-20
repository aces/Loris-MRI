"""This class gather functions for candidate handling."""

import random
from dateutil.parser import parse
import lib.exitcode
import sys

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
        self.psc_id     = psc_id
        self.cand_id    = cand_id
        self.sex        = sex
        self.dob        = dob
        self.age        = None
        self.center_id  = None
        self.project_id = None

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

        if not self.psc_id:
            print("Cannot create a candidate without a PSCID.\n")
            sys.exit(lib.exitcode.CANDIDATE_CREATION_FAILURE)

        if not self.cand_id:
            self.cand_id = self.generate_cand_id(db)

        for row in participants_info:
            if not row['participant_id'] == self.psc_id:
                continue
            self.grep_bids_dob(row)
            if 'sex' in row:
                self.map_sex(row['sex'])
            if 'age' in row:
                self.age = row['age']

            # three steps to find site:
            #   1. try matching full name from 'site' column in participants.tsv in db
            #   2. try extracting alias from pscid
            #   3. try finding previous site in candidate table

            if 'site' in row and row['site'].lower() not in ("null", ""):
                # search site id in psc table by its full name
                site_info = db.pselect(
                    "SELECT CenterID FROM psc WHERE Name = %s",
                    [row['site'], ]
                )
                if len(site_info) > 0:
                    self.center_id = site_info[0]['CenterID']

            if self.center_id is None:
                # search site id in psc table by its alias extracted from pscid
                db_sites = db.pselect("SELECT CenterID, Alias FROM psc")
                for site in db_sites:
                    if site['Alias'] in row['participant_id']:
                        self.center_id = site['CenterID']

            if self.center_id is None:
                # try to find participant site in db
                candidate_site_project = db.pselect(
                    "SELECT RegistrationCenterID FROM candidate WHERE pscid = %s",
                    [self.psc_id, ]
                )
                if len(candidate_site_project) > 0:
                    self.center_id = candidate_site_project[0]['RegistrationCenterID']

            # two steps to find project:
            #   1. find full name in 'project' column in participants.tsv
            #   2. find previous in candidate table

            if 'project' in row and row['project'].lower() not in ("null", ""):
                # search project id in Project table by its full name
                project_info = db.pselect(
                    "SELECT ProjectID FROM Project WHERE Name = %s",
                    [row['project'], ]
                )
                if len(project_info) > 0:
                    self.project_id = project_info[0]['ProjectID']

            if self.project_id is None:
                # try to find participant project
                candidate_site_project = db.pselect(
                    "SELECT RegistrationProjectID FROM candidate WHERE pscid = %s",
                    [self.psc_id, ]
                )
                if len(candidate_site_project) > 0:
                    self.center_id = candidate_site_project[0]['RegistrationProjectID']

        if not self.center_id:
            print("ERROR: could not determine site for " + self.psc_id + "."
                  + " Please check that your psc table contains a site with an"
                  + " alias matching the BIDS participant_id or a name matching the site mentioned in"
                  + " participants.tsv's site column")
            sys.exit(lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE)

        if not self.project_id:
            print("ERROR: could not determine project for " + self.psc_id + "."
                  + " Please check that your project table contains a project with a"
                  + " name matching the participants.tsv's project column")
            sys.exit(lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE)

        if self.verbose:
            print("Creating candidate with \n"
                  + "PSCID     = " + self.psc_id + ",\n"
                  + "CandID    = " + str(self.cand_id) + ",\n"
                  + "CenterID  = " + str(self.center_id)  + ",\n"
                  + "ProjectID = " + str(self.project_id))

        insert_col = ('PSCID', 'CandID', 'RegistrationCenterID', 'RegistrationProjectID')
        insert_val = (self.psc_id, str(self.cand_id), str(self.center_id), str(self.project_id))

        if self.sex:
            insert_col = insert_col + ('Sex',)
            insert_val = insert_val + (self.sex,)
        if self.dob:
            insert_col = insert_col + ('DoB',)
            insert_val = insert_val + (self.dob,)

        db.insert(
            table_name='candidate',
            column_names=insert_col,
            values=insert_val
        )

        return self.get_candidate_info_from_loris(db)

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

        while db.pselect("SELECT * FROM candidate WHERE CandID = %s", (id,)):
            # pick a new id
            id = random.randint(100000, 999999)

        return id
