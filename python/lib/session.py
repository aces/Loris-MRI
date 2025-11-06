"""This class gather functions for session handling."""

from lib.database_lib.candidate_db import CandidateDB


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

        self.candidate_db_obj = CandidateDB(db, verbose)

        self.cand_id = str(cand_id)
        self.visit_label = visit_label
        self.center_id = center_id
        self.project_id = project_id
        self.cohort_id = cohort_id

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
            column_names = (*column_names, 'ProjectID')
            values = (*values, str(self.project_id))

        if self.cohort_id:
            column_names = (*column_names, 'CohortID')
            values = (*values, str(self.cohort_id))

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
