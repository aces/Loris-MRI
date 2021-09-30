"""This class gather functions for session handling."""

from lib.database_lib.session_db import SessionDB
__license__ = "GPLv3"


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
            center_id, project_id, subproject_id
        )

        # grep session information from the database
        loris_vl_info = session.get_session_info_from_loris(db)

        # insert the session into the database
        loris_vl_info = session.create_session(db)

        # disconnect from the database
        db.disconnect()
    """

    def __init__(self, db, verbose, cand_id=None, visit_label=None,
                 center_id=None, project_id=None, subproject_id=None):
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
        :param subproject_id: subproject ID to associate with the session
         :type subproject_id: int
        """
        self.db = db
        self.verbose = verbose

        self.session_db_obj = SessionDB(db, verbose)

        self.cand_id = str(cand_id)
        self.visit_label = visit_label
        self.center_id = center_id
        self.project_id = project_id
        self.subproject_id = subproject_id

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

        column_names = ('CandID', 'Visit_label', 'CenterID', 'Current_stage')
        values = (self.cand_id, self.visit_label, str(self.center_id), 'Not Started')

        if self.project_id:
            column_names = column_names + ('ProjectID',)
            values = values + (str(self.project_id),)

        if self.subproject_id:
            column_names = column_names + ('SubprojectID',)
            values = values + (str(self.subproject_id),)

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
            "SELECT * FROM session WHERE CandID = %s AND Visit_label = %s",
            (self.cand_id, self.visit_label)
        )

        return loris_session_info[0] if loris_session_info else None

    def get_session_center_info(self, pscid, visit_label):

        return self.session_db_obj.get_session_center_info(pscid, visit_label)

    def create_session_dict(self, cand_id, visit_label):

        self.session_info_dict = self.session_db_obj.create_session_dict(cand_id, visit_label)
        if self.session_info_dict:
            self.cand_id = self.session_info_dict['CandID']
            self.visit_label = self.session_info_dict['Visit_label']
            self.center_id = self.session_info_dict['CenterID']
            self.project_id = self.session_info_dict['ProjectID']
            self.subproject_id = self.session_info_dict['SubprojectID']
            self.session_id = self.session_info_dict['ID']

    def insert_into_session(self, session_info_to_insert_dict):

        self.session_id = self.session_db_obj.insert_into_session(
            fields=session_info_to_insert_dict.keys(),
            values=session_info_to_insert_dict.values
        )

        return self.session_id

    def get_next_session_site_id_and_visit_number(self, cand_id):

        return self.session_db_obj.determine_next_session_site_id_and_visit_number(cand_id)
