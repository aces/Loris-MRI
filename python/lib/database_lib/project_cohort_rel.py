"""This class performs project_cohort_rel table related database queries and common checks"""


__license__ = "GPLv3"


class ProjectCohortRel:
    """
    This class performs database queries for project_cohort_rel table.

    :Example:

        from lib.database_lib.project_cohort_rel import ProjectCohortRel
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        project_cohort_rel_obj = ProjectCohortRel(db, verbose)

        ...
    """

    def __init__(self, db, verbose):
        """
        Constructor method for the ProjectCohortRel class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def create_proj_cohort_rel_dict(self, project_id, cohort_id):
        """
        Get the project/cohort rel information for a given project ID and cohort ID.

        :param project_id: ID of the Project
         :type project_id: int
        :param cohort_id: ID of the cohort
         :type cohort_id: int

        :return: dictionary of the project/cohort rel
         :rtype: dict
        """

        query = "SELECT * FROM project_cohort_rel" \
                " JOIN Project USING (ProjectID)" \
                " JOIN cohort USING (CohortID)" \
                " WHERE ProjectID=%s AND CohortID=%s"
        results = self.db.pselect(query=query, args=(project_id, cohort_id))

        return results[0] if results else None
