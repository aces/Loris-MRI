"""This class performs database queries for the physiological_parameter_file table"""


__license__ = "GPLv3"


class PhysiologicalParameterFile:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalParameterFile class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_parameter_file'
        self.verbose = verbose

    def insert(self, physiological_file_id, project_id, parameter_type_id, value):
        """
        Inserts a new entry in the physiological_event_file table.

        :param physiological_file_id    : physiological file's ID
         :type physiological_file_id    : int
        :param project_id               : Project ID
         :type project_id               : int
        :param parameter_type_id        : type of the parameter
         :type parameter_type_id        : int
        :param value                    : value of the parameter
         :type value                    : str

        :return                  : id of the row inserted
         :rtype                  : int
        """

        return self.db.insert(
            table_name   = self.table,
            column_names = ('PhysiologicalFileID', 'ProjectID', 'ParameterTypeID', 'Value'),
            values       = (physiological_file_id, project_id, parameter_type_id, value),
            get_last_id  = True
        )
