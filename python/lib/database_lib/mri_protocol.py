"""This class performs database queries for the site (mri_protocol) tables"""


__license__ = "GPLv3"


class MriProtocol:

    def __init__(self, db, verbose):
        """
        Constructor method for the MriProtocol class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db = db
        self.verbose = verbose

    def get_list_of_protocols_based_on_session_info(
            self, project_id, subproject_id, center_id, visit_label, scanner_id
    ):
        """

        """

        query = "SELECT * FROM mri_protocol" \
                " JOIN mri_protocol_group_target mpgt USING (MriProtocolGroupID)" \
                " WHERE (" \
                "   (CenterID = %s AND ScannerID = %s)" \
                "   OR (CenterID IS NULL AND ScannerID IS NULL)" \
                ")"

        query += " AND (mpgt.ProjectID IS NULL OR mpgt.ProjectID = %s)" \
            if project_id else " AND mpgt.ProjectID IS NULL"
        query += " AND (mpgt.SubprojectID IS NULL OR mpgt.SubprojectID = %s)" \
            if subproject_id else " AND mpgt.SubprojectID IS NULL"
        query += " AND (mpgt.Visit_label IS NULL OR mpgt.Visit_label = %s)" \
            if visit_label else " AND mpgt.Visit_label IS NULL"
        query += " ORDER BY CenterID ASC, ScannerID DESC"

        args_list = [center_id, scanner_id]
        if project_id:
            args_list.append(project_id)
        if subproject_id:
            args_list.append(subproject_id)
        if visit_label:
            args_list.append(visit_label)

        results = self.db.pselect(query=query, args=tuple(args_list))

        return results

    def get_bids_info_for_scan_type_id(self, scan_type_id):

        query = """
            SELECT 
                bmstr.MRIScanTypeID,
                bids_category.BIDSCategoryName,
                bids_scan_type_subcategory.BIDSScanTypeSubCategory,
                bids_scan_type.BIDSScanType,
                bmstr.BIDSEchoNumber,
                bids_phase_encoding_direction.BIDSPhaseEncodingDirectionName,
                mst.Scan_type
            FROM bids_mri_scan_type_rel
                JOIN      mri_scan_type mst             ON mst.ID = bmstr.MRIScanTypeID
                JOIN      bids_category                 USING (BIDSCategoryID)
                JOIN      bids_scan_type                USING (BIDSScanTypeID)
                LEFT JOIN bids_scan_type_subcategory    USING (BIDSScanTypeSubCategoryID)
                LEFT JOIN bids_phase_encoding_direction USING (BIDSPhaseEncodingDirectionID)
            WHERE 
                mst.ID = %s
        """

        results = self.db.pselect(query=query, args=(scan_type_id,))

        return results if results else None
