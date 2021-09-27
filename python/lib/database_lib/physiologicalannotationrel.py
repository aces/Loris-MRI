"""This class performs database queries for the physiological_annotation_rel table"""


__license__ = "GPLv3"


class PhysiologicalAnnotationRel:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalAnnotationRel class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_annotation_rel'
        self.verbose = verbose

    def insert(self, annotation_data_id, annotation_metadata_id):
        """
        Inserts a new entry in the physiological_annotation_rel table.

        :param annotation_data_id : ID of the annotation TSV file
         :type annotation_data_id : int
        :param annotation_metadata_id : ID of the annotation JSON file
         :type annotation_metadata_id : int
        """

        self.db.insert(
            table_name   = self.table,
            column_names = ('AnnotationTSV', 'AnnotationJSON'),
            values       = (annotation_data_id, annotation_metadata_id)
        )
