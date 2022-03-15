"""This class performs database queries for the physiological_event_parameter table"""


__license__ = "GPLv3"


class PhysiologicalEventParameterCategoryLevel:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalEventParameter class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_event_parameter'
        self.verbose = verbose

    def insert(self, event_parameter_id, level_name, description, hed):
        """
        Inserts a new entry in the physiological_event_parameter table.

        :param event_parameter_id : event parameter's ID
         :type event_parameter_id : int

        :param level_name         : Name of the event parameter's categorical level
         :type level_name         : string 

        :param description        : Description of the event parameter's categorical level
         :type description        : string 

        :param hed                : Event parameter's categorical HED tag
         :type hed                : string
        """

        self.db.insert(
            table_name   = self.table,
            column_names = ('EventParameterID', 'LevelName', 'Description', 'HED'),
            values       = (event_parameter_id, level_name, description, hed)
            get_last_id  = True
        )

    def grep_id_from_physiological_file_id(self, physiological_file_id):
        """
        Gets the EventParameterID given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : id of the row if found or None
         :rtype                      : int
        """

        paramID = self.db.pselect(
            query="SELECT EventParameterID "
            "FROM " + self.table + " p "
            "JOIN physiological_event_file f ON f.EventFileID = p.EventFileID "
            "WHERE f.PhysiologicalFileID = %s "
            "LIMIT 1",
            args=(physiological_file_id,)
        )

        return paramID[0]['EventParameterID'] if paramID else None
