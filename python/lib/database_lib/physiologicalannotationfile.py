"""This class performs database queries for the physiological_annotation_file table"""


__license__ = "GPLv3"


class PhysiologicalAnnotationFile:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalAnnotationFile class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_annotation_file'
        self.verbose = verbose

    def insert(self, physiological_file_id, annotation_file_type, annotation_file):
        """
        Inserts a new entry in the physiological_annotation_file table.

        :param physiological_file_id : physiological file's ID
         :type physiological_file_id : int

        :param annotation_file_type  : type of the annotation file
         :type annotation_file_type  : str

        :param annotation_file       : path of the annotation file
         :type annotation_file       : str

        :return                      : id of the row inserted
         :rtype                      : int
        """

        return self.db.insert(
            table_name   = self.table,
            column_names = ('PhysiologicalFileID', 'FileType', 'FilePath'),
            values       = (physiological_file_id, annotation_file_type, annotation_file),
            get_last_id  = True
        )

    def grep_annotation_paths_from_physiological_file_id(self, physiological_file_id):
        """
        Gets the FilePath given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : list of FilePath if any or None
         :rtype                      : list
        """

        annotation_paths = self.db.pselect(
            query = "SELECT DISTINCT FilePath "
                    "FROM physiological_annotation_file "
                    "WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

        annotation_paths = [annotation_path['FilePath'] for annotation_path in annotation_paths]
