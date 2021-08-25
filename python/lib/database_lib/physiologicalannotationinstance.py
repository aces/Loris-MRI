"""This class performs database queries for the physiological_annotation_instance table"""


__license__ = "GPLv3"


class PhysiologicalAnnotationInstance:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalAnnotationInstance class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_annotation_instance'
        self.verbose = verbose

    def grep_annotation_from_physiological_file_id(self, physiological_file_id):
        """
        Greps all entries present in the physiological_annotation_instance,
        physiological_annotation_file, physiological_annotation_label and
        physiological_annotation_parameter tables for a
        given PhysiologicalFileID and returns its result.

        :param physiological_file_id: physiological file's ID
         :type physiological_file_id: int

        :return: tuple of dictionaries with one entry in the tuple
                 corresponding to one entry in physiological_annotation_instance
         :rtype: tuple
        """

        results = self.db.pselect(
            query="SELECT * "
                  "FROM " + self.table + " i "
                  "JOIN physiological_annotation_file f ON i.AnnotationFileID = f.AnnotationFileID "
                  "JOIN physiological_annotation_label l ON l.AnnotationLabelID = i.AnnotationLabelID "
                  "JOIN physiological_annotation_parameter p ON p.AnnotationFileID = i.AnnotationFileID "
                  "WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

        return results

    def insert(self, annotation_data):
        """
        Inserts a new entry in the physiological_annotation_instance table.

        :param annotation_data : Annotation data
         :type annotation_data : list
        """

        self.db.insert(
            table_name   = self.table,
            column_names = (
                'AnnotationFileID', 'AnnotationParameterID', 'Onset', 'Duration',
                'AnnotationLabelID', 'Channels', 'AbsoluteTime', 'Description'
            ),
            values       = annotation_data
        )
