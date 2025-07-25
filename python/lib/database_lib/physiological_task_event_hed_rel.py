"""This class performs database queries for the physiological_task_event_hed_rel table"""


class PhysiologicalTaskEventHEDRel:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalTaskEventHEDRel class.

        :param db                : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_task_event_hed_rel'
        self.verbose = verbose

    def insert(self, target_id, hed_tag_id, tag_value, has_pairing,
               pair_rel_id, additional_members):
        """
        Inserts a new entry in the physiological_task_event_hed_rel table.

        :param target_id            : ProjectID or EventFileID
         :type target_id            : int
        :param hed_tag_id           : HEDTagID - ID PK from hed_schema_nodes table
         :type hed_tag_id           : int
        :param tag_value            : Value of tag, if value tag
         :type tag_value            : str | None
        :param has_pairing          : Has Pairing
         :type has_pairing          : bool
        :param pair_rel_id          : ID of pair
         :type pair_rel_id          : int
        :param additional_members   : Number of additional members in group
         :type additional_members   : int

        :return                     : id of the row inserted
         :rtype                     : int
        """
        column_names = (
            'PhysiologicalTaskEventID',
            'HEDTagID',
            'TagValue',
            'HasPairing',
            'PairRelID',
            'AdditionalMembers'
        )
        values = (
            target_id,
            hed_tag_id,
            tag_value,
            has_pairing,
            pair_rel_id,
            additional_members
        )
        return self.db.insert(
            table_name=self.table,
            column_names=column_names,
            values=values,
            get_last_id=True
        )
