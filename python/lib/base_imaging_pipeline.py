import os
import sys

import lib.exitcode
import lib.utilities
from lib.database import Database
from lib.database_lib.config import Config
from lib.database_lib.notification import Notification
from lib.database_lib.mriupload import MriUpload
from lib.database_lib.mriscanner import MriScanner
from lib.database_lib.site import Site
from lib.database_lib.tarchive import Tarchive
from lib.imaging import Imaging
from lib.log import Log


class BaseImagingPipeline:
    """
    Series of checks done by most scripts from the imaging pipeline
    """

    def __init__(self, loris_getopt_obj):
        """
        This initialize runs all the base functions that are always run by the following scripts:
        - nifti_insertion.py
        - tarchive_validation.py
        - tarchive_loader.py

        These includes the following steps:
        - load pipeline options
        - establish database connection
        - load the Config, Imaging, Tarchive, MriUpload, MriScanner, Site, Notification and other classes
        - creates the processing temporary directory
        - creates the log file for the script execution
        - populate the mri_upload and tarchive info dictionaries
        - determine the subject IDs
        - determine the site information
        - determine the scanner information

        Note: if any of the steps above fails, errors are logged and the script execution will end
        """

        # ----------------------------------------------------
        # load pipeline options
        # ----------------------------------------------------
        self.loris_getopt_obj = loris_getopt_obj
        self.config_file = loris_getopt_obj.config_info
        self.options_dict = loris_getopt_obj.options_dict
        self.verbose = self.options_dict["verbose"]["value"]

        # ----------------------------------------------------
        # establish database connection
        # ----------------------------------------------------
        self.db = Database(self.config_file.mysql, self.verbose)
        self.db.connect()

        # -----------------------------------------------------------------------------------
        # load the Config, Imaging, Tarchive, MriUpload, MriScanner and Site classes
        # -----------------------------------------------------------------------------------
        self.config_db_obj = Config(self.db, self.verbose)
        self.mri_upload_db_obj = MriUpload(self.db, self.verbose)
        self.mri_scanner_db_obj = MriScanner(self.db, self.verbose)
        self.site_db_obj = Site(self.db, self.verbose)
        self.tarchive_db_obj = Tarchive(self.db, self.verbose, self.config_file)
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)

        # ---------------------------------------------------------------------------------------------
        # grep config settings from the Config module
        # ---------------------------------------------------------------------------------------------
        self.data_dir = self.config_db_obj.get_config("dataDirBasepath")
        self.dicom_lib_dir = self.config_db_obj.get_config('tarchiveLibraryDir')

        # ---------------------------------------------------------------------------------------------
        # create tmp dir and log file (their basename being the name of the script run)
        # ---------------------------------------------------------------------------------------------
        script_name = os.path.basename(__file__[:-3])
        self.tmp_dir = lib.utilities.create_processing_tmp_dir(script_name)
        self.log_obj = Log(self.data_dir, script_name, os.path.basename(self.tmp_dir), self.options_dict)
        self.log_obj.write_to_log_file("\t==> Successfully connected to database\n")

        # ---------------------------------------------------------------------------------------------
        # Load mri_upload and tarchive dictionary
        # ---------------------------------------------------------------------------------------------
        self.load_mri_upload_and_tarchive_dictionaries()

        # ---------------------------------------------------------------------------------------------
        # Create the notification object now that we have a confirmed UploadID
        # ---------------------------------------------------------------------------------------------
        self.notification_obj = Notification(
            self.db,
            self.verbose,
            notification_type=f"PYTHON {script_name.replace('_', ' ').upper()}",
            notification_origin=f"{script_name}.py",
            process_id=self.mri_upload_db_obj.mri_upload_dict["UploadID"]
        )

        # ---------------------------------------------------------------------------------
        # determine subject IDs based on DICOM headers and validate the IDs against the DB
        # ---------------------------------------------------------------------------------
        self.subject_id_dict = self.determine_subject_ids()

        # ----------------------------------------------------
        # verify PSC information stored in DICOMs
        # ----------------------------------------------------
        self.site_dict = self.determine_study_info()
        message = f"\t==> Found Center Name: {self.site_dict['CenterName']}," \
                  f" Center ID: {str(self.site_dict['CenterID'])}\n"
        self.log_info(message, is_error="N", is_verbose="Y")

        # ---------------------------------------------------------------
        # grep scanner information based on what is in the DICOM headers
        # ---------------------------------------------------------------
        self.scanner_dict = self.determine_scanner_info()

    def load_mri_upload_and_tarchive_dictionaries(self):
        """
        Loads the mri_upload and tarchive info dictionaries based on the content of the mri_upload
        and tarchive tables found for the processed UploadID/ArchiveLocation given as argument to
        the script.
        """

        upload_id = self.options_dict["upload_id"]["value"]
        tarchive_path = self.options_dict["tarchive_path"]["value"]
        success = False
        err_msg = ''
        if upload_id:
            success, err_msg = self.mri_upload_db_obj.create_mri_upload_dict("UploadID", upload_id)
            if success and self.mri_upload_db_obj.mri_upload_dict["TarchiveID"]:
                tarchive_id = self.mri_upload_db_obj.mri_upload_dict["TarchiveID"]
                success = self.tarchive_db_obj.create_tarchive_dict(tarchive_id=tarchive_id)
                if not success:
                    err_msg += f"[ERROR   ] Could not load tarchive dictionary for TarchiveID {tarchive_id}\n"
        elif tarchive_path:
            archive_location = tarchive_path.replace(self.dicom_lib_dir, "")
            success = self.tarchive_db_obj.create_tarchive_dict(archive_location=archive_location)
            if not success:
                err_msg += f"[ERROR   ] Could not load tarchive dictionary for ArchiveLocation {archive_location}\n"
            else:
                tarchive_id = self.tarchive_db_obj.tarchive_info_dict["TarchiveID"]
                success, new_err_msg = self.mri_upload_db_obj.create_mri_upload_dict("TarchiveID", tarchive_id)
                if not success:
                    err_msg += new_err_msg
        if not success:
            self.log_error_and_exit(err_msg, lib.exitcode.SELECT_FAILURE, is_error="Y", is_verbose="N")

    def determine_study_info(self):
        """
        Determine the study center associated to the DICOM archive based on a DICOM header
        specified by the lookupCenterNameUsing config setting.

        :return: dictionary with CenterName and CenterID information
         :rtype: dict
        """

        cand_id = self.subject_id_dict['CandID']
        visit_label = self.subject_id_dict['visitLabel']
        patient_name = self.subject_id_dict['PatientName']

        # get the CenterID from the session table if the PSCID and visit label exists
        # and could be extracted from the database
        if cand_id and visit_label:
            # TODO move query in a session database_lib??
            query = "SELECT s.CenterID AS CenterID, p.MRI_alias AS CenterName" \
                    " FROM session s" \
                    " JOIN psc p ON p.CenterID=s.CenterID" \
                    " WHERE s.CandID = %s AND s.Visit_label = %s"
            results = self.db.pselect(query=query, args=(cand_id, visit_label))
            if results:
                return results[0]

        # if could not find center information based on cand_id and visit_label, use the
        # patient name to match it to the site alias or MRI alias
        list_of_sites = self.site_db_obj.get_list_of_sites()
        for site_dict in list_of_sites:
            if site_dict['Alias'] in patient_name:
                return {'CenterName': site_dict['Alias'], 'CenterID': site_dict['CenterID']}
            elif site_dict['MRI_alias'] in patient_name:
                return {'CenterName': site_dict['MRI_alias'], 'CenterID': site_dict['CenterID']}

        # if we got here, it means we could not find a center associated to the dataset
        self.log_error_and_exit(
            message="ERROR: No center found for this DICOM study",
            exit_code=lib.exitcode.SELECT_FAILURE,
            is_error="Y",
            is_verbose="N"
        )

    def determine_scanner_info(self):
        """
        Determine the scanner information found in the database for the uploaded DICOM archive.
        """
        scanner_dict = self.mri_scanner_db_obj.determine_scanner_information(
            self.tarchive_db_obj.tarchive_info_dict, self.site_dict
        )
        message = f"===> Found Scanner ID: {str(scanner_dict['ScannerID'])}"
        self.log_info(message, is_error="N", is_verbose="Y")
        return scanner_dict

    def determine_subject_ids(self):
        """
        Determine subject IDs based on the DICOM header specified by the lookupCenterNameUsing
        config setting. This function will call a function in the config file that can be
        customized for each project.

        :return subject_id_dict: dictionary with subject IDs and visit label or error status
         :rtype subject_id_dict: dict
        """

        dicom_header = self.config_db_obj.get_config('lookupCenterNameUsing')
        dicom_value = self.tarchive_db_obj.tarchive_info_dict[dicom_header]
        scanner_id = self.scanner_dict['ScannerID']
        subject_id_dict = None

        try:
            subject_id_dict = self.config_file.get_subject_ids(self.db, dicom_value, scanner_id)
            subject_id_dict['PatientName'] = dicom_value
        except AttributeError:
            message = "[ERROR   ] config file does not contain a get_subject_ids routine. Upload will exit now.\n"
            self.log_error_and_exit(message, lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE, is_error="Y", is_verbose="N")

        return subject_id_dict

    def validate_subject_ids(self):
        """
        Ensure that the subject PSCID/CandID corresponds to a single candidate in the candidate
        table and that the visit label can be found in the Visit_Windows table. If those
        conditions are not fulfilled, then a 'CandMismatchError' with the validation error
        is added to the subject IDs dictionary (subject_id_dict).
        """

        psc_id = self.subject_id_dict["PSCID"]
        cand_id = self.subject_id_dict["CandID"]
        visit_label = self.subject_id_dict["visitLabel"]
        is_phantom = self.subject_id_dict["isPhantom"]

        # no further checking if the subject is phantom
        if is_phantom:
            return

        # check that the CandID and PSCID are valid
        # TODO: move the query in a database_lib class specific to the candidate table
        query = "SELECT c1.CandID, c2.PSCID AS PSCID " \
                " FROM candidate c1 " \
                " LEFT JOIN candidate c2 ON (c1.CandID=c2.CandID AND c2.PSCID = %s) " \
                " WHERE c1.CandID = %s"
        results = self.db.pselect(query=query, args=(psc_id, cand_id))
        if not results:
            # if no rows were returned, then the CandID is not valid
            self.subject_id_dict["message"] = f"=> Could not find candidate with CandID={cand_id} in the database"
            self.subject_id_dict["CandMismatchError"] = "CandID does not exist"
        elif not results[0]["PSCID"]:
            # if no PSCID returned in the row, then PSCID and CandID do not match
            self.subject_id_dict["message"] = "=> PSCID and CandID of the image mismatch"
            self.subject_id_dict["CandMismatchError"] = self.subject_id_dict['message']

        # check if visit label is valid
        # TODO: move the query in a database_lib class specific to the candidate table
        query = 'SELECT Visit_label FROM Visit_Windows WHERE BINARY Visit_label = %s'
        results = self.db.pselect(query=query, args=(visit_label,))
        if results:
            self.subject_id_dict["message"] = f"=> Found visit label {visit_label} in Visit_Windows"
        elif self.subject_id_dict["createVisitLabel"]:
            self.subject_id_dict["message"] = f"=> Will create visit label {visit_label} in Visit_Windows"
        else:
            self.subject_id_dict["message"] = f"=> Visit Label {visit_label} does not exist in Visit_Windows"
            self.subject_id_dict["CandMismatchError"] = self.subject_id_dict['message']

        upload_id = self.mri_upload_db_obj.mri_upload_dict["UploadID"]
        if self.subject_id_dict["CandMismatchError"]:
            # if there is a candidate mismatch error, log it but do not exit. It will be logged later in SQL table
            self.log_info(self.subject_id_dict["CandMismatchError"], is_error="Y", is_verbose="N")
            self.mri_upload_db_obj.update_mri_upload(
                upload_id=upload_id, fields=('IsCandidateInfoValidated',), values=('0',)
            )
        else:
            self.log_info(self.subject_id_dict["message"], is_error="N", is_verbose="Y")
            self.mri_upload_db_obj.update_mri_upload(
                upload_id=upload_id, fields=('IsCandidateInfoValidated',), values=('1',)
            )

    def log_error_and_exit(self, message, exit_code, is_error, is_verbose):
        """
        Function to commonly executes all logging information when the script needs to be
        interrupted due to an error. It will log the error in the log file created by the
        script being executed, add an entry with the error in the notification_spool table
        and print the error to the user in the terminal.
        """
        self.log_obj.write_to_log_file(message)
        self.notification_obj.write_to_notification_spool(message, is_error, is_verbose)
        print(message)
        sys.exit(exit_code)

    def log_info(self, message, is_error, is_verbose):
        """
        Function to commonly executes logging information that need to be logged in the
        notification table and in the log file produced by the script executed
        """
        self.log_obj.write_to_log_file(message)
        self.notification_obj.write_to_notification_spool(message, is_error, is_verbose)
        if self.verbose:
            print(message)
