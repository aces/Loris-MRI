import os
import re
import shutil
import sys

import lib.exitcode
import lib.utilities
from lib.database import Database
from lib.database_lib.config import Config
from lib.database_lib.notification import Notification
from lib.database_lib.mriupload import MriUpload
from lib.database_lib.mriscanner import MriScanner
from lib.database_lib.project_subproject_rel import ProjectSubprojectRel
from lib.database_lib.session import Session
from lib.database_lib.site import Site
from lib.database_lib.tarchive import Tarchive
from lib.log import Log


class BasePipeline:
    """
    Series of checks done by most scripts from the imaging pipeline
    """

    def __init__(self, loris_getopt_obj, script_name):
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
        # Load pipeline options
        # ----------------------------------------------------
        self.loris_getopt_obj = loris_getopt_obj
        self.config_file = loris_getopt_obj.config_info
        self.options_dict = loris_getopt_obj.options_dict
        self.verbose = self.options_dict["verbose"]["value"]
        self.upload_id = loris_getopt_obj.options_dict["upload_id"]["value"]

        # ----------------------------------------------------
        # Establish database connection
        # ----------------------------------------------------
        self.db = Database(self.config_file.mysql, self.verbose)
        self.db.connect()

        # -----------------------------------------------------------------------------------
        # Load the Config, Imaging, Tarchive, MriUpload, MriScanner and Site classes
        # -----------------------------------------------------------------------------------
        self.config_db_obj = Config(self.db, self.verbose)
        self.mri_upload_db_obj = MriUpload(self.db, self.verbose)
        self.mri_scanner_db_obj = MriScanner(self.db, self.verbose)
        self.session_db_obj = Session(self.db, self.verbose)
        self.site_db_obj = Site(self.db, self.verbose)
        self.proj_subproj_rel_db_obj = ProjectSubprojectRel(self.db, self.verbose)
        self.tarchive_db_obj = Tarchive(self.db, self.verbose, self.config_file)
        self.notification_obj = None  # set this to none until we get an confirmed UploadID

        # ---------------------------------------------------------------------------------------------
        # Grep config settings from the Config module
        # ---------------------------------------------------------------------------------------------
        self.data_dir = self.config_db_obj.get_config("dataDirBasepath")
        self.dicom_lib_dir = self.config_db_obj.get_config('tarchiveLibraryDir')

        # ---------------------------------------------------------------------------------------------
        # Create tmp dir and log file (their basename being the name of the script run)
        # ---------------------------------------------------------------------------------------------
        self.tmp_dir = lib.utilities.create_processing_tmp_dir(script_name)
        self.log_obj = Log(self.data_dir, script_name, os.path.basename(self.tmp_dir), self.options_dict)
        self.log_info("Successfully connected to database", is_error="N", is_verbose="Y")

        # ---------------------------------------------------------------------------------------------
        # Load mri_upload and tarchive dictionary
        # ---------------------------------------------------------------------------------------------
        self.load_mri_upload_and_tarchive_dictionaries()

        # ---------------------------------------------------------------------------------------------
        # Set Inserting field of mri_upload to indicate a script is running on the upload
        # and load the notification object
        # ---------------------------------------------------------------------------------------------
        if "UploadID" in self.mri_upload_db_obj.mri_upload_dict.keys():
            self.upload_id = self.mri_upload_db_obj.mri_upload_dict["UploadID"]
            self.mri_upload_db_obj.update_mri_upload(upload_id=self.upload_id, fields=('Inserting',), values=('1',))

            # Create the notification object now that we have a confirmed UploadID
            self.notification_obj = Notification(
                self.db,
                self.verbose,
                notification_type=f"PYTHON {script_name.replace('_', ' ').upper()}",
                notification_origin=f"{script_name}.py",
                process_id=self.mri_upload_db_obj.mri_upload_dict["UploadID"]
            )

        # ---------------------------------------------------------------------------------
        # Determine subject IDs based on DICOM headers and validate the IDs against the DB
        # Verify PSC information stored in DICOMs
        # Grep scanner information based on what is in the DICOM headers
        # ---------------------------------------------------------------------------------
        if self.tarchive_db_obj.tarchive_info_dict.keys():
            self.subject_id_dict = self.determine_subject_ids(scanner_id=None)

            # verify PSC information stored in DICOMs
            self.site_dict = self.determine_study_info()
            message = f"Found Center Name: {self.site_dict['CenterName']}," \
                      f" Center ID: {str(self.site_dict['CenterID'])}"
            self.log_info(message, is_error="N", is_verbose="Y")

            # grep scanner information based on what is in the DICOM headers
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
                    err_msg += f"Could not load tarchive dictionary for TarchiveID {tarchive_id}"
        elif tarchive_path:
            archive_location = tarchive_path.replace(self.dicom_lib_dir, "")
            success = self.tarchive_db_obj.create_tarchive_dict(archive_location=archive_location)
            if not success:
                err_msg += f"Could not load tarchive dictionary for ArchiveLocation {archive_location}"
            else:
                tarchive_id = self.tarchive_db_obj.tarchive_info_dict["TarchiveID"]
                success, new_err_msg = self.mri_upload_db_obj.create_mri_upload_dict("TarchiveID", tarchive_id)
                if not success:
                    err_msg += new_err_msg
        if not success and not self.options_dict["force"]["value"]:
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
            self.session_db_obj.create_session_dict(cand_id, visit_label)
            session_dict = self.session_db_obj.session_info_dict
            return {"CenterName": session_dict["MRI_alias"], "CenterID": session_dict["CenterID"]}

        # if could not find center information based on cand_id and visit_label, use the
        # patient name to match it to the site alias or MRI alias
        list_of_sites = self.site_db_obj.get_list_of_sites()
        for site_dict in list_of_sites:
            if site_dict["Alias"] in patient_name:
                return {"CenterName": site_dict["Alias"], "CenterID": site_dict["CenterID"]}
            elif site_dict["MRI_alias"] in patient_name:
                return {"CenterName": site_dict["MRI_alias"], "CenterID": site_dict["CenterID"]}

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
        message = f"Found Scanner ID: {str(scanner_dict['ScannerID'])}"
        self.log_info(message, is_error="N", is_verbose="Y")
        return scanner_dict

    def determine_subject_ids(self, scanner_id):
        """
        Determine subject IDs based on the DICOM header specified by the lookupCenterNameUsing
        config setting. This function will call a function in the config file that can be
        customized for each project.

        :return subject_id_dict: dictionary with subject IDs and visit label or error status
         :rtype subject_id_dict: dict
        """

        dicom_header = self.config_db_obj.get_config('lookupCenterNameUsing')
        dicom_value = self.tarchive_db_obj.tarchive_info_dict[dicom_header]
        subject_id_dict = None

        try:
            subject_id_dict = self.config_file.get_subject_ids(self.db, dicom_value, scanner_id)
            subject_id_dict["PatientName"] = dicom_value
        except AttributeError:
            message = "Config file does not contain a get_subject_ids routine. Upload will exit now."
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
            self.subject_id_dict["message"] = f"Found visit label {visit_label} in Visit_Windows"
        elif self.subject_id_dict["createVisitLabel"]:
            self.subject_id_dict["message"] = f"Will create visit label {visit_label} in Visit_Windows"
        else:
            self.subject_id_dict["message"] = f"Visit Label {visit_label} does not exist in Visit_Windows"
            self.subject_id_dict["CandMismatchError"] = self.subject_id_dict['message']

        if "CandMismatchError" in self.subject_id_dict.keys():
            # if there is a candidate mismatch error, log it but do not exit. It will be logged later in SQL table
            self.log_info(self.subject_id_dict["CandMismatchError"], is_error="Y", is_verbose="N")
            self.mri_upload_db_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('0',)
            )
        else:
            self.log_info(self.subject_id_dict["message"], is_error="N", is_verbose="Y")
            self.mri_upload_db_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('1',)
            )

    def log_error_and_exit(self, message, exit_code, is_error, is_verbose):
        """
        Function to commonly executes all logging information when the script needs to be
        interrupted due to an error. It will log the error in the log file created by the
        script being executed, add an entry with the error in the notification_spool table
        and print the error to the user in the terminal.
        """
        err_msg = f"[ERROR   ] {message}"
        self.log_obj.write_to_log_file(f"\n{err_msg}\n")
        if self.notification_obj:
            self.notification_obj.write_to_notification_spool(err_msg, is_error, is_verbose)
        if self.upload_id:
            self.mri_upload_db_obj.update_mri_upload(upload_id=self.upload_id, fields=("Inserting",), values=("0",))
        print(f"\n{err_msg}\n")
        sys.exit(exit_code)

    def log_info(self, message, is_error, is_verbose):
        """
        Function to commonly executes logging information that need to be logged in the
        notification table and in the log file produced by the script executed
        """
        log_msg = f"==> {message}"
        self.log_obj.write_to_log_file(f"{log_msg}\n")
        if self.notification_obj:
            self.notification_obj.write_to_notification_spool(log_msg, is_error, is_verbose)
        if self.verbose:
            print(f"{log_msg}\n")

    def get_session_info(self):

        cand_id = self.subject_id_dict["CandID"]
        visit_label = self.subject_id_dict["visitLabel"]
        self.session_db_obj.create_session_dict(cand_id, visit_label)

        if self.session_db_obj.session_info_dict.keys():
            message = f"Session ID for the file to insert is {self.session_db_obj.session_info_dict['ID']}"
            self.log_info(message, is_error="N", is_verbose="Y")

    def create_session(self):
        cand_id = self.subject_id_dict["CandID"]
        visit_label = self.subject_id_dict["visitLabel"]
        create_visit_label = self.subject_id_dict["createVisitLabel"]
        project_id = self.subject_id_dict["ProjectID"] if "ProjectID" in self.subject_id_dict.keys() else None
        subproject_id = self.subject_id_dict["SubprojectID"] if "SubprojectID" in self.subject_id_dict.keys() else None

        # check if whether the visit label should be created
        if not create_visit_label:
            message = f"Visit {visit_label} for candidate {cand_id} does not exist."
            self.log_error_and_exit(message, lib.exitcode.GET_SESSION_ID_FAILURE, is_error="Y", is_verbose="N")

        # check if a project ID was provided in the config file for the visit label
        if not project_id:
            message = "Cannot create visit: profile file does not defined the visit's ProjectID"
            self.log_error_and_exit(message, lib.exitcode.CREATE_SESSION_FAILURE, is_error="Y", is_verbose="N")

        # check if a subproject ID was provided in the config file for the visit label
        if not subproject_id:
            message = "Cannot create visit: profile file does not defined the visit's SubprojectID"
            self.log_error_and_exit(message, lib.exitcode.CREATE_SESSION_FAILURE, is_error="Y", is_verbose="N")

        # check that the project ID and subproject ID refers to an existing row in project_subproject_rel table
        self.proj_subproj_rel_db_obj.create_proj_subproj_rel_dict(project_id, subproject_id)
        if not self.proj_subproj_rel_db_obj.proj_subproj_rel_info_dict.keys():
            message = f"Cannot create visit with project ID {project_id} and subproject ID {subproject_id}:" \
                      f" no such association in table project_subproject_rel"
            self.log_error_and_exit(message, lib.exitcode.CREATE_SESSION_FAILURE, is_error="Y", is_verbose="N")

        # determine the visit number and center ID for the next session to be created
        center_id, visit_nb = self.determine_new_session_site_and_visit_nb()
        if not center_id:
            message = f"No center ID found for candidate {cand_id}, visit {visit_label}"
            self.log_error_and_exit(message, is_error="Y", is_verbose="N")
        else:
            message = f"Set newVisitNo = {visit_nb} and center ID = {center_id}"
            self.log_info(message, is_error="N", is_verbose="Y")

        # create the new visit
        session_id = self.session_db_obj.insert_into_session(
            fields=(
                "CandID",    "Visit_label", "CenterID",     "VisitNo",  "Current_stage",
                "Scan_done", "Submitted",   "SubprojectID", "ProjectID"
            ),
            values=(
                cand_id, visit_label, center_id,     visit_nb,   "Not Started",
                "Y",     "N",         subproject_id, project_id
            )
        )
        if session_id:
            self.get_session_info()

    def determine_new_session_site_and_visit_nb(self):
        cand_id = self.subject_id_dict["CandID"]
        visit_label = self.subject_id_dict["visitLabel"]
        is_phantom = self.subject_id_dict["isPhantom"]
        visit_nb = 0
        center_id = 0

        if is_phantom:
            center_info_dict = self.determine_phantom_data_site(string_with_site_acronym=visit_label)
            if center_info_dict:
                center_id = center_info_dict["CenterID"]
                visit_nb = 1
        else:
            center_info_dict = self.session_db_obj.determine_next_session_site_id_and_visit_number(cand_id)
            if center_info_dict:
                center_id = center_info_dict["CenterID"]
                visit_nb = center_info_dict["newVisitNo"]

        return center_id, visit_nb

    def determine_phantom_data_site(self, string_with_site_acronym):

        pscid = self.subject_id_dict["PSCID"]
        visit_label = self.subject_id_dict["visitLabel"]

        # first check whether there is already a session in the database for the phantom scan
        if pscid and visit_label:
            return self.session_db_obj.get_session_center_info(pscid, visit_label)

        # if no session found, use a string_with_site_acronym to match it to a site alias or MRI alias
        for row in self.site_dict:
            if re.search(rf"{row['Alias']}|{row['MRI_alias']}", string_with_site_acronym, re.IGNORECASE):
                return row

    def check_if_tarchive_validated_in_db(self):
        """
        Checks whether the DICOM archive was previously validated in the database (as per the value present
        in the <IsTarchiveValidated> field of the <mri_upload> table.

        If the DICOM archive was not validated, the pipeline will exit and log the proper error information.
        """
        mu_dict = self.mri_upload_db_obj.mri_upload_dict
        if ("IsTarchiveValidated" not in mu_dict.keys() or not mu_dict["IsTarchiveValidated"]) and not self.force:
            err_msg = f"The DICOM archive validation has failed for UploadID {self.upload_id}. Either run the" \
                      f" validation again and fix the problem or use --force to force the insertion of the NIfTI file."
            self.log_error_and_exit(err_msg, lib.exitcode.INVALID_DICOM, is_error="Y", is_verbose="N")

    def create_dir(self, directory_path):

        if not os.path.exists(directory_path):
            self.log_info(f'Creating directory {directory_path}', is_error='N', is_verbose='Y')
            os.makedirs(directory_path)
            if not os.path.exists(directory_path):
                message = f'Failed creating directory {directory_path}'
                self.log_error_and_exit(message, lib.exitcode.CREATE_DIR_FAILURE, is_error='Y', is_verbose='N')

    def move_file(self, old_file_path, new_file_path):

        self.log_info(f'Moving {old_file_path} to {new_file_path}', is_error='N', is_verbose='Y')
        shutil.move(old_file_path, new_file_path, self.verbose)
        if not os.path.exists(new_file_path):
            message = f'Could not move {old_file_path} to {new_file_path}'
            self.log_error_and_exit(message, lib.exitcode.COPY_FAILURE, is_error='Y', is_verbose='N')
