"""This class performs database queries for the physiological_annotation_parameter table"""


__license__ = "GPLv3"


class PhysiologicalAnnotationParameter:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalAnnotationParameter class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_annotation_parameter'
        self.verbose = verbose

    def insert(self, annotation_file_id, sources, author):
        """
        Inserts a new entry in the physiological_annotation_parameter table.

        :param annotation_file_id : annotation file's ID
         :type annotation_file_id : int

        :param sources            : Description of the file(s) used to make the annotations
         :type sources            : string

        :param author             : Annotation's author
         :type author             : string
        """

        self.db.insert(
            table_name   = self.table,
            column_names = ('AnnotationFileID', 'Sources', 'Author'),
            values       = (annotation_file_id, sources, author)
        )

    def grep_id_from_physiological_file_id(self, physiological_file_id):
        """
        Gets the AnnotationParameterID given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : id of the row if found or None
         :rtype                      : int
        """

        paramID = self.db.pselect(
            query="SELECT AnnotationParameterID "
            "FROM " + self.table + " p "
            "JOIN physiological_annotation_file f ON f.AnnotationFileID = p.AnnotationFileID "
            "WHERE f.PhysiologicalFileID = %s "
            "LIMIT 1",
            args=(physiological_file_id,)
        )

        return paramID[0]['AnnotationParameterID'] if paramID else None
