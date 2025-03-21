"""This class performs database queries for the mri_protocol tables"""


__license__ = "GPLv3"


class MriProtocol:
    """
    This class performs database queries for imaging dataset stored in the mri_protocol table.

    :Example:

        from lib.mri_protocol import MriProtocol
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        mri_prot_db_obj = MriProtocol(db, verbose)

        ...
    """

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
            self, project_id, cohort_id, center_id, visit_label, scanner_id
    ):
        """
        Grep the list of imaging protocols available based on session information.

        :param project_id: `ProjectID` associated to the scanning session
         :type project_id: int
        :param cohort_id: `CohortID` associated to the scanning session
         :type cohort_id: int
        :param center_id: `CenterID` associated to the scanning session
         :type center_id: int
        :param visit_label: `VisitLabel` associated to the scanning session
         :type visit_label: str
        :param scanner_id: `ScannerID` of the scanner used to acquire the scans
         :type scanner_id: int

        :return: list of matching MRI protocols from the `mri_protocol` table
         :rtype: list
        """

        query = "SELECT * FROM mri_protocol" \
                " JOIN mri_protocol_group_target mpgt USING (MriProtocolGroupID)" \
                " WHERE (" \
                "   (CenterID = %s AND ScannerID = %s)" \
                "   OR (CenterID IS NULL AND ScannerID IS NULL)" \
                ")"

        query += " AND (mpgt.ProjectID IS NULL OR mpgt.ProjectID = %s)" \
            if project_id else " AND mpgt.ProjectID IS NULL"
        query += " AND (mpgt.CohortID IS NULL OR mpgt.CohortID = %s)" \
            if cohort_id else " AND mpgt.CohortID IS NULL"
        query += " AND (mpgt.Visit_label IS NULL OR mpgt.Visit_label = %s)" \
            if visit_label else " AND mpgt.Visit_label IS NULL"
        query += " ORDER BY CenterID ASC, ScannerID DESC"

        args_list = [center_id, scanner_id]
        if project_id:
            args_list.append(project_id)
        if cohort_id:
            args_list.append(cohort_id)
        if visit_label:
            args_list.append(visit_label)

        results = self.db.pselect(query=query, args=tuple(args_list))

        return results

    def get_bids_info_for_scan_type_id(self, scan_type_id):
        """
        Get the BIDS information to name and organize the data according to the BIDS specifications.
            - BIDSCategoryName corresponds to the name of the BIDS subfolder to move the NIfTI file into
              (a.k.a. `anat`, `func`, `fmap`, `dwi`, `asl`...)
            - BIDSScanTypeSubCategory corresponds to the list of BIDS entity/value to use to name the files
              (examples: `task-rest`, `acq-25direction` or other. Note, in the DB these will be separated with
              underscores: example: `task-rest_acq-xxx`)
            - BIDSScanType corresponds to the scan type to be used when naming the file (example: `T1w`, `T2w`, `bold`)
            - BIDSEchoNumber: echo number to be used with `echo-` for multi-echo images (example: `1`, `2`...)
            - BIDSPhaseEncodingDirectionName: the PhaseEncodingDirection stored in the JSON file
              (possible values: "i", "j", "k", "i-", "j-", "k-". The letters i, j, k correspond to the first,
              second and third axis of the data in the NIFTI file.)

        :param scan_type_id: Scan type ID from the mri_scan_type table to use to get the BIDS information
         :type scan_type_id: int

        :return: dictionary with the BIDS information to use to name and move the NIfTI file according to the BIDS spec
         :rtype: dict
        """

        query = """
            SELECT
                bmstr.MRIScanTypeID,
                bids_category.BIDSCategoryName,
                bids_scan_type_subcategory.BIDSScanTypeSubCategory,
                bids_scan_type.BIDSScanType,
                bmstr.BIDSEchoNumber,
                bids_phase_encoding_direction.BIDSPhaseEncodingDirectionName,
                mst.MriScanTypeName AS ScanType
            FROM bids_mri_scan_type_rel bmstr
                JOIN      mri_scan_type mst             ON mst.MriScanTypeID = bmstr.MRIScanTypeID
                JOIN      bids_category                 USING (BIDSCategoryID)
                JOIN      bids_scan_type                USING (BIDSScanTypeID)
                LEFT JOIN bids_scan_type_subcategory    USING (BIDSScanTypeSubCategoryID)
                LEFT JOIN bids_phase_encoding_direction USING (BIDSPhaseEncodingDirectionID)
            WHERE
                mst.MriScanTypeID = %s
        """

        results = self.db.pselect(query=query, args=(scan_type_id,))

        return results[0] if results else None
