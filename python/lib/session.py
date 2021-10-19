"""This class gather functions for session handling."""

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

    def __init__(self, verbose, cand_id, visit_label,
                 center_id, project_id, subproject_id):
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
        self.verbose = verbose

        self.cand_id       = str(cand_id)
        self.visit_label   = visit_label
        self.center_id     = center_id
        self.project_id    = project_id
        self.subproject_id = subproject_id


    def create_session(self, db):
        """
        Creates a session using BIDS information.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """

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

        db.insert(
            table_name='session',
            column_names=column_names,
            values=values
        )

        loris_session_info = self.get_session_info_from_loris(db)

        return loris_session_info


    def get_session_info_from_loris(self, db):
        """
        Grep session information from the session table using CandID and
        Visit_label.

        :param db: database handler object
         :type db: object

        :return: dictionary with session info from the session's table
         :rtype: dict
        """

        loris_session_info = db.pselect(
            "SELECT * FROM session WHERE CandID = %s AND Visit_label = %s",
            (self.cand_id, self.visit_label)
        )

        return loris_session_info[0] if loris_session_info else None

    def start_visit_stage(self, db, api, visit_date):
        """
        Start the visit using BIDS information.

        :param db        : database handler object
         :type db        : object
        :param visit_date: visit date
         :type visit_date: date
        """

        if self.verbose:
            print("Starting visit stage for " + self.visit_label + " and CandID "  + self.cand_id)

        if not self.subproject_id or not self.project_id:
            print("Can't start the visit stage - No subproject and project associated with the participant data.")
            return

        site = db.grep_id_from_lookup_table('Name', 'psc', 'CenterID', self.center_id)
        subproject = db.grep_id_from_lookup_table('title', 'subproject', 'SubprojectID', self.subproject_id)
        project = db.grep_id_from_lookup_table('Name', 'Project', 'ProjectID', self.project_id)
        date = visit_date[0:10]

        api.start_next_stage(self.cand_id, self.visit_label, site, subproject, project, date)
