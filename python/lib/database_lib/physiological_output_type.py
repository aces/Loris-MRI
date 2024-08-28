"""This class performs database queries for the physiological_output_type table"""


__license__ = "GPLv3"


class PhysiologicalOutputType:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalOutputType class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_output_type'
        self.verbose = verbose

    def grep_id_from_output_type(self, physiological_output_type):
        """
        Gets rows given a physiological_output_type

        :param physiological_output_type : PhysiologicalOutputType -- ['raw', 'derivative']
        :type physiological_output_type : string

        :return                      : PhysiologicalOutputTypeID of physiological_output_type
         :rtype                      : int
        """

        return self.db.grep_id_from_lookup_table(
            id_field_name='PhysiologicalOutputTypeID',
            table_name=self.table,
            where_field_name='OutputTypeName',
            where_value=physiological_output_type,
            insert_if_not_found=False
        )
