"""This class performs database queries for the site (mri_protocol_checks) tables"""


__license__ = "GPLv3"


class MriProtocolChecks:

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

    def get_list_of_possible_protocols_based_on_session_info(self, session_info_dict, scan_type_id):
        """

        """

        project_id = session_info_dict["ProjectID"]
        subproject_id = session_info_dict["SubprojectID"]
        visit_label = session_info_dict["Visit_label"]

        query = "SELECT * FROM mri_protocol_checks" \
                " JOIN mri_protocol_checks_group_target mpcgt USING (MriProtocolChecksGroupID)" \
                " WHERE Scan_type = %s "

        query += " AND (mpcgt.ProjectID IS NULL OR mpcgt.ProjectID = %s)" \
            if project_id else " AND mpcgt.ProjectID IS NULL"
        query += " AND (mpcgt.SubprojectID IS NULL OR mpcgt.SubprojectID = %s)" \
            if subproject_id else " AND mpcgt.SubprojectID IS NULL"
        query += " AND (mpcgt.Visit_label IS NULL OR mpcgt.Visit_label = %s)" \
            if visit_label else " AND mpcgt.Visit_label IS NULL"

        args_list = [scan_type_id]
        if project_id:
            args_list.append(project_id)
        if subproject_id:
            args_list.append(subproject_id)
        if visit_label:
            args_list.append(visit_label)

        return self.db.pselect(query=query, args=tuple(args_list))
