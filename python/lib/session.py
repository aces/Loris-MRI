"""This class gather functions for session handling."""

from typing_extensions import deprecated

from lib.database_lib.candidate_db import CandidateDB
from lib.database_lib.project_cohort_rel import ProjectCohortRel
from lib.database_lib.session_db import SessionDB
from lib.database_lib.site import Site


class Session:
    """
    This class gather functions that interact with the database and allow session
    creation or to fetch session information directly from the database.

    :Example:

        from lib.session  import Session
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        session = Session(
            verbose, cand_id, visit_label,
            center_id, project_id, cohort_id
        )

        # grep session information from the database
        loris_vl_info = session.get_session_info_from_loris(db)

        # insert the session into the database
        loris_vl_info = session.create_session(db)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, db, verbose, cand_id=None, visit_label=None,
                 center_id=None, project_id=None, cohort_id=None):
        """
        Constructor method for the Session class.

        :param verbose      : whether to be verbose
         :type verbose      : bool
        :param cand_id      : candidate's CandID
         :type cand_id      : int
        :param visit_label  : visit label
         :type visit_label  : str
        :param center_id    : center ID to associate with the session
         :type center_id    : int
        :param project_id   : project ID to associate with the session
         :type project_id   : int
        :param cohort_id: cohort ID to associate with the session
         :type cohort_id: int
        """
        self.db = db
        self.verbose = verbose

        self.proj_cohort_rel_db_obj = ProjectCohortRel(db, verbose)
        self.candidate_db_obj = CandidateDB(db, verbose)
        self.session_db_obj = SessionDB(db, verbose)
        self.site_db_obj = Site(db, verbose)

        self.cand_id = str(cand_id)
        self.visit_label = visit_label
        self.center_id = center_id
        self.project_id = project_id
        self.cohort_id = cohort_id

        self.proj_cohort_rel_info_dict = dict()
        self.session_info_dict = dict()
        self.session_id = None

    def create_session(self):
        """
        Creates a session using BIDS information.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """
        # TODO refactor bids_import pipeline to use same functions as dcm2bids below. To be done in different PR though
        if self.verbose:
            print("Creating visit " + self.visit_label
                  + " for CandID "  + self.cand_id)

        # fetch the candidate.ID associated to the CandID first
        candidate_id = self.candidate_db_obj.get_candidate_id(self.cand_id)
        column_names = ('CandidateID', 'Visit_label', 'CenterID', 'Current_stage')
        values = (candidate_id, self.visit_label, str(self.center_id), 'Not Started')

        if self.project_id:
            column_names = column_names + ('ProjectID',)
            values = values + (str(self.project_id),)

        if self.cohort_id:
            column_names = column_names + ('CohortID',)
            values = values + (str(self.cohort_id),)

        self.db.insert(
            table_name='session',
            column_names=column_names,
            values=values
        )

        loris_session_info = self.get_session_info_from_loris()

        return loris_session_info

    def get_session_info_from_loris(self):
        """
        Grep session information from the session table using CandID and
        Visit_label.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """
        # TODO refactor bids_import pipeline to use same functions as dcm2bids below. To be done in different PR though
        loris_session_info = self.db.pselect(
            """
            SELECT PSCID, CandID, session.*
            FROM session
                JOIN candidate ON (candidate.ID=session.CandidateID)
            WHERE CandID = %s AND Visit_label = %s
            """,
            (self.cand_id, self.visit_label)
        )

        return loris_session_info[0] if loris_session_info else None

    @deprecated('Use `lib.db.queries.site.try_get_site_with_psc_id_visit_label` instead')
    def get_session_center_info(self, pscid, visit_label):
        """
        Get the session center information based on the PSCID and visit label of a session.

        :param pscid: candidate site ID (PSCID)
         :type pscid: str
        :param visit_label: visit label
         :type visit_label: str

        :return: dictionary of site information for the visit/candidate queried
         :rtype: dict
        """
        return self.session_db_obj.get_session_center_info(pscid, visit_label)

    @deprecated('Use `lib.db.queries.try_get_candidate_with_cand_id_visit_label` instead')
    def create_session_dict(self, cand_id, visit_label):
        """
        Creates the session information dictionary based on a candidate ID and visit label. This will populate
        self.session_info_dict based on the result returned from the database query.

        :param cand_id: CandID
         :type cand_id: int
        :param visit_label: Visit label of the session
         :type visit_label: str
        """
        self.session_info_dict = self.session_db_obj.create_session_dict(cand_id, visit_label)
        if self.session_info_dict:
            self.cand_id = self.session_info_dict['CandID']
            self.visit_label = self.session_info_dict['Visit_label']
            self.center_id = self.session_info_dict['CenterID']
            self.project_id = self.session_info_dict['ProjectID']
            self.cohort_id = self.session_info_dict['CohortID']
            self.session_id = self.session_info_dict['ID']

    @deprecated('Use `lib.db.models.session.DbSession` instead')
    def insert_into_session(self, session_info_to_insert_dict):
        """
        Insert a new row in the session table using fields list as column names and values as values.

        :param session_info_to_insert_dict: dictionary with the column names and values to use for insertion
         :type session_info_to_insert_dict: dict

        :return: ID of the new session registered
         :rtype: int
        """
        self.session_id = self.session_db_obj.insert_into_session(
            fields=list(session_info_to_insert_dict.keys()),
            values=list(session_info_to_insert_dict.values())
        )

        return self.session_id

    @deprecated('Use `lib.get_subject_session.get_candidate_next_visit_number` instead')
    def get_next_session_site_id_and_visit_number(self, cand_id):
        """
        Determines the next session site and visit number based on the last session inserted for a given candidate.

        :param cand_id: candidate ID
         :type cand_id: int

        :return: a dictionary with 'newVisitNo' and 'CenterID' keys/values
         :rtype: dict
        """
        return self.session_db_obj.determine_next_session_site_id_and_visit_number(cand_id)

    @deprecated('Use `lib.db.queries.site.get_all_sites` instead')
    def get_list_of_sites(self):
        """
        Get the list of sites available in the psc table.

        :return: list of sites
         :rtype: list
        """

        return self.site_db_obj.get_list_of_sites()

    @deprecated('Use `lib.db.models.project_cohort.DbProjectCohort` instead')
    def create_proj_cohort_rel_info_dict(self, project_id, cohort_id):
        """
        Populate self.proj_cohort_rel_info_dict with the content returned from the database for the ProjectID and
        CohortID.

        :param project_id: ID of the Project
         :type project_id: int
        :param cohort_id: ID of the Cohort
         :type cohort_id: int
        """
        self.proj_cohort_rel_info_dict = self.proj_cohort_rel_db_obj.create_proj_cohort_rel_dict(
            project_id, cohort_id
        )
