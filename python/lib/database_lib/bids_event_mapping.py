"""This class performs bids_event_*_mapping related database queries"""


class BidsEventMapping:

    def __init__(self, db, verbose):
        """
        Constructor method for the BidsEventMapping class.

        :param db                : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.dataset_mapping_table = 'bids_event_dataset_mapping'
        self.file_mapping_table = 'bids_event_file_mapping'
        self.verbose = verbose

    def insert(self, target_id, property_name, property_value, hed_tag_id,
               tag_value, description, has_pairing, pair_rel_id,
               additional_members, project_wide):
        """
        Inserts a new entry in the bids_event_*_mapping table.

        :param target_id            : ProjectID or EventFileID
         :type target_id            : int
        :param property_name        : Name of property
         :type property_name        : str
        :param property_value       : Value of the property
         :type property_value       : str
        :param hed_tag_id           : HEDTagID - ID PK from hed_schema_nodes table
         :type hed_tag_id           : int
        :param tag_value            : Value of tag, if value tag
         :type tag_value            : str | None
        :param description          : Mapping Description
         :type description          : str
        :param has_pairing          : Has Pairing
         :type has_pairing          : bool
        :param pair_rel_id          : ID of pair
         :type pair_rel_id          : int
        :param additional_members   : Number of additional members in group
         :type additional_members   : int
        :param project_wide         : True if dataset mapping, otherwise file mapping
         :type project_wide         : bool

        :return                     : id of the row inserted
         :rtype                     : int
        """
        column_names = (
            'ProjectID' if project_wide else 'EventFileID',
            'PropertyName', 'PropertyValue', 'HEDTagID',
            'TagValue', 'Description', 'HasPairing', 'PairRelID',
            'AdditionalMembers'
        )
        values = (
            target_id, property_name, property_value, hed_tag_id,
            tag_value, description, has_pairing, pair_rel_id,
            additional_members
        )
        return self.db.insert(
            table_name=self.dataset_mapping_table if project_wide else self.file_mapping_table,
            column_names=column_names,
            values=values,
            get_last_id=True
        )
