"""This class performs database queries for the physiological_modality table"""


class PhysiologicalModality:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalModality class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_modality'
        self.verbose = verbose

    def grep_id_from_modality_value(self, physiological_modality):
        """
        Gets rows given a physiological_modality

        :param physiological_modality       : PhysiologicalModality -- ['eeg', 'ieeg', 'meg']
        :type physiological_modality        : string

        :return                             : PhysiologicalModalityID of physiological_modality
         :rtype                             : int
        """

        return self.db.grep_id_from_lookup_table(
            id_field_name='PhysiologicalModalityID',
            table_name=self.table,
            where_field_name='PhysiologicalModality',
            where_value=physiological_modality,
            insert_if_not_found=False
        )
