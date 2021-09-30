"""This class performs project_subproject_rel table related database queries and common checks"""


__license__ = "GPLv3"


class ProjectSubprojectRel:
    """
    This class performs database queries for project_subproject_rel table.

    :Example:

        from lib.database_lib.project_subproject_rel import ProjectSubprojectRel
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        project_subproject_rel_obj = ProjectSubprojectRel(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the ProjectSubprojectRel class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def create_proj_subproj_rel_dict(self, project_id, subproject_id):
        """
        Get the project/subproject rel information for a given project ID and subproject ID.

        :param project_id: ID of the Project
         :type project_id: int
        :param subproject_id: ID of the Subproject
         :type subproject_id: int

        :return: dictionary of the project/subproject rel
         :rtype: dict
        """

        query = "SELECT * FROM project_subproject_rel" \
                " JOIN Project USING (ProjectID)" \
                " JOIN subproject USING (SubprojectID)" \
                " WHERE ProjectID=%s AND SubprojectID=%s"
        results = self.db.pselect(query=query, args=(project_id, subproject_id))

        return results[0] if results else None
