"""This class performs database queries for the physiological_event_archive table"""


__license__ = "GPLv3"


class PhysiologicalEventArchive:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalEventArchive class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_event_archive'
        self.verbose = verbose

    def grep_from_physiological_file_id(self, physiological_file_id):
        """
        Gets rows given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : list of dict containing rows data if found or None
         :rtype                      : list
        """

        return self.db.pselect(
            query="SELECT * FROM " + self.table + " WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

    def insert(self, physiological_file_id, blake2, archive_path):
        """
        Inserts a new entry in the physiological_event_archive table.

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :param blake2                : blake2b hash
         :type blake2                : string

        :param archive_path          : Archive's path
         :type archive_path          : string
        """

        self.db.insert(
            table_name   = self.table,
            column_names = ('PhysiologicalFileID', 'Blake2bHash', 'FilePath'),
            values       = (physiological_file_id, blake2, archive_path)
        )
