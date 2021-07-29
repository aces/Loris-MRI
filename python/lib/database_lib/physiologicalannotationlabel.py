"""This class performs database queries for the physiological_annotation_label table"""

import datetime

__license__ = "GPLv3"


class PhysiologicalAnnotationLabel:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalAnnotationLabel class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_annotation_label'
        self.verbose = verbose

    def insert(self, labelData):
        """
        Inserts a new entry in the physiological_annotation_label table.

        :param labelData : list of tuples (labelName, labelDescription)
         :type labelData : list
        """

        self.db.insert(
            table_name   = self.table,
            column_names = ('LabelName', 'LabelDescription'),
            values       = labelData
        )

    def grep_id(self, label, insert_if_not_found):
        """
        Gets the physiological_annotation_label AnnotationLabelID given a labelName

        :param label               : labelName
         :type label               : string

        :param insert_if_not_found : if value is inserted if not found
         :type insert_if_not_found : bool

        :return                      : id of the row if found or None
         :rtype                      : int
        """

        return self.db.grep_id_from_lookup_table(
            'AnnotationLabelID', self.table, 'LabelName', label, insert_if_not_found=insert_if_not_found
        )

