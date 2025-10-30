"""This class performs database queries for the mri_protocol_checks tables"""


class MriProtocolChecks:
    """
    This class performs database queries for imaging dataset stored in the mri_protocol_checks table.

    :Example:

        from lib.mri_protocol_checks import MriProtocolChecks
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_prot_checks_db_obj = MriProtocolChecks(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the MriProtocolChecks class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def get_list_of_possible_protocols_based_on_session_info(
            self, project_id, cohort_id, visit_label, scan_type_id
    ):
        """
        Grep the list of imaging protocols checks to use based on session information.

        :param project_id: `ProjectID` associated to the scanning session
         :type project_id: int
        :param cohort_id: `CohortID` associated to the scanning session
         :type cohort_id: int
        :param visit_label: `VisitLabel` associated to the scanning session
         :type visit_label: str
        :param scan_type_id: ID of the scan type associated to the NIfTI file
         :type scan_type_id: int

        :return: list of matching MRI protocol checks from the `mri_protocol_checks` table
         :rtype: list
        """

        query = "SELECT * FROM mri_protocol_checks" \
                " JOIN mri_protocol_checks_group_target mpcgt USING (MriProtocolChecksGroupID)" \
                " WHERE MriScanTypeID = %s "

        query += " AND (mpcgt.ProjectID IS NULL OR mpcgt.ProjectID = %s)" \
            if project_id else " AND mpcgt.ProjectID IS NULL"
        query += " AND (mpcgt.CohortID IS NULL OR mpcgt.CohortID = %s)" \
            if cohort_id else " AND mpcgt.CohortID IS NULL"
        query += " AND (mpcgt.Visit_label IS NULL OR mpcgt.Visit_label = %s)" \
            if visit_label else " AND mpcgt.Visit_label IS NULL"

        args_list = [scan_type_id]
        if project_id:
            args_list.append(project_id)
        if cohort_id:
            args_list.append(cohort_id)
        if visit_label:
            args_list.append(visit_label)

        return self.db.pselect(query=query, args=tuple(args_list))
