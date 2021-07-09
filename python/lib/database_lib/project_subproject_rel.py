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

        # this will contain the tarchive info
        self.proj_subproj_rel_info_dict = dict()

    def create_proj_subproj_rel_dict(self, project_id, subproject_id):

        query = f"SELECT * FROM project_subproject_rel" \
                f" JOIN Project USING (ProjectID)" \
                f" JOIN subproject USING (SubprojectID)" \
                f" WHERE ProjectID=%s AND SubprojectID=%s"
        results = self.db.pselect(query=query, args=(project_id, subproject_id))

        if results:
            self.proj_subproj_rel_info_dict = results[0]
