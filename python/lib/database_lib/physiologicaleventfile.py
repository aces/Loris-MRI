"""This class performs database queries for the physiological_event_file table"""


__license__ = "GPLv3"


class PhysiologicalEventFile:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalEventFile class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_event_file'
        self.verbose = verbose

    def insert(self, physiological_file_id, event_file_type, event_file):
        """
        Inserts a new entry in the physiological_event_file table.

        :param physiological_file_id : physiological file's ID
         :type physiological_file_id : int

        :param event_file_type  : type of the event file
         :type event_file_type  : str

        :param event_file       : path of the event file
         :type event_file       : str

        :return                      : id of the row inserted
         :rtype                      : int
        """

        return self.db.insert(
            table_name   = self.table,
            column_names = ('PhysiologicalFileID', 'FileType', 'FilePath'),
            values       = (physiological_file_id, event_file_type, event_file),
            get_last_id  = True
        )

    def grep_event_paths_from_physiological_file_id(self, physiological_file_id):
        """
        Gets the FilePath given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : list of FilePath if any or None
         :rtype                      : list
        """

        event_paths = self.db.pselect(
            query = "SELECT DISTINCT FilePath "
                    "FROM physiological_event_file "
                    "WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

        event_paths = [event_path['FilePath'] for event_path in event_paths]
