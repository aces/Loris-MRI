import os
import re
import shutil
import sys
from typing import Never

from lib.exception.determine_subject_exception import DetermineSubjectException
from lib.exception.validate_subject_exception import ValidateSubjectException
import lib.exitcode
import lib.utilities

from lib.database_lib.config import Config
from lib.database import Database
from lib.db.connect import connect_to_database
from lib.db.query.session import try_get_session_with_cand_id_visit_label
from lib.dicom_archive import DicomArchive
from lib.imaging import Imaging
from lib.log import Log
from lib.imaging_upload import ImagingUpload
from lib.session import Session
from lib.validate_subject_ids import validate_subject_ids


class BasePipeline:
    """
    Series of checks done by most scripts of the dcm2bids imaging pipeline.
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
        - load the Config, Imaging, Tarchive, ImagingUpload, Session and other classes
        - creates the processing temporary directory
        - creates the log file for the script execution
        - populate the imaging_upload and tarchive info dictionaries
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
        self.force = self.options_dict["force"]["value"] if "force" in self.options_dict else None
        self.verbose = self.options_dict["verbose"]["value"]
        self.upload_id = loris_getopt_obj.options_dict["upload_id"]["value"]

        # ----------------------------------------------------
        # Establish database connection
        # ----------------------------------------------------
        self.db = Database(self.config_file.mysql, self.verbose)
        self.db.connect()

        self.db_orm = connect_to_database(self.config_file.mysql)

        # -----------------------------------------------------------------------------------
        # Load the Config, Imaging, ImagingUpload, Tarchive, Session database classes
        # -----------------------------------------------------------------------------------
        self.config_db_obj = Config(self.db, self.verbose)
        self.dicom_archive_obj = DicomArchive(self.db, self.verbose)
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)
        self.imaging_upload_obj = ImagingUpload(self.db, self.verbose)
        self.session_obj = Session(self.db, self.verbose)

        # ---------------------------------------------------------------------------------------------
        # Grep config settings from the Config module
        # ---------------------------------------------------------------------------------------------
        self.data_dir = self.config_db_obj.get_config("dataDirBasepath")
        self.dicom_lib_dir = self.config_db_obj.get_config('tarchiveLibraryDir')

        # ---------------------------------------------------------------------------------------------
        # Create tmp dir and log file (their basename being the name of the script run)
        # ---------------------------------------------------------------------------------------------
        self.tmp_dir = self.loris_getopt_obj.tmp_dir
        self.log_obj = Log(
            self.db, self.data_dir, script_name, os.path.basename(self.tmp_dir), self.options_dict, self.verbose
        )
        self.log_info("Successfully connected to database", is_error="N", is_verbose="Y")

        # ---------------------------------------------------------------------------------------------
        # Load imaging_upload and tarchive dictionary
        # ---------------------------------------------------------------------------------------------
        self.load_imaging_upload_and_tarchive_dictionaries()

        # ---------------------------------------------------------------------------------------------
        # Set Inserting field of mri_upload to indicate a script is running on the upload
        # and load the notification object
        # ---------------------------------------------------------------------------------------------
        if "UploadID" in self.imaging_upload_obj.imaging_upload_dict.keys():
            self.upload_id = self.imaging_upload_obj.imaging_upload_dict["UploadID"]
            self.imaging_upload_obj.update_mri_upload(upload_id=self.upload_id, fields=('Inserting',), values=('1',))

            # Initiate the notification object now that we have a confirmed UploadID
            self.log_obj.initiate_notification_db_obj(self.upload_id)

        # ---------------------------------------------------------------------------------
        # Determine subject IDs based on DICOM headers and validate the IDs against the DB
        # Verify PSC information stored in DICOMs
        # Grep scanner information based on what is in the DICOM headers
        # ---------------------------------------------------------------------------------
        if self.dicom_archive_obj.tarchive_info_dict.keys():
            try:
                self.subject = self.imaging_obj.determine_subject_ids(self.dicom_archive_obj.tarchive_info_dict)
            except DetermineSubjectException as exception:
                self.log_error_and_exit(
                    exception.message,
                    lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE,
                    is_error="Y",
                    is_verbose="N"
                )

            # verify PSC information stored in DICOMs
            self.site_dict = self.determine_study_info()
            message = f"Found Center Name: {self.site_dict['CenterName']}," \
                      f" Center ID: {str(self.site_dict['CenterID'])}"
            self.log_info(message, is_error="N", is_verbose="Y")

            # grep scanner information based on what is in the DICOM headers
            self.scanner_id = self.determine_scanner_info()

    def load_imaging_upload_and_tarchive_dictionaries(self):
        """
        Loads the imaging_upload and tarchive info dictionaries based on the content of the imaging_upload
        and tarchive tables found for the processed UploadID/ArchiveLocation given as argument to
        the script.
        """

        upload_id = self.options_dict["upload_id"]["value"]
        tarchive_path = self.options_dict["tarchive_path"]["value"] \
            if "tarchive_path" in self.options_dict.keys() else None
        success = False
        err_msg = ''
        if upload_id and tarchive_path:
            self.imaging_upload_obj.create_imaging_upload_dict_from_upload_id(upload_id)
            if not self.imaging_upload_obj.imaging_upload_dict:
                err_msg += f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}."
                self.log_error_and_exit(err_msg, lib.exitcode.SELECT_FAILURE, is_error="Y", is_verbose="N")
            tarchive_id = self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]
            if not tarchive_id:
                err_msg += f"UploadID {upload_id} is not linked to any tarchive in mri_upload."
                self.log_error_and_exit(err_msg, lib.exitcode.SELECT_FAILURE, is_error="Y", is_verbose="N")
            self.dicom_archive_obj.populate_tarchive_info_dict_from_tarchive_id(tarchive_id=tarchive_id)
            db_archive_location = self.dicom_archive_obj.tarchive_info_dict['ArchiveLocation']
            if os.path.join(self.data_dir, 'tarchive', db_archive_location) != tarchive_path:
                err_msg += f"UploadID {upload_id} and ArchiveLocation {tarchive_path} do not refer to the same upload"
                self.log_error_and_exit(err_msg, lib.exitcode.SELECT_FAILURE, is_error="Y", is_verbose="N")

        if upload_id:
            self.imaging_upload_obj.create_imaging_upload_dict_from_upload_id(upload_id)
            if not self.imaging_upload_obj.imaging_upload_dict:
                err_msg += f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}"
            else:
                if self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]:
                    tarchive_id = self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]
                    self.dicom_archive_obj.populate_tarchive_info_dict_from_tarchive_id(tarchive_id=tarchive_id)
                    if self.dicom_archive_obj.tarchive_info_dict:
                        success = True
                    else:
                        err_msg += f"Could not load tarchive dictionary for TarchiveID {tarchive_id}"

        elif tarchive_path:
            archive_location = tarchive_path.replace(self.dicom_lib_dir, "")
            self.dicom_archive_obj.populate_tarchive_info_dict_from_archive_location(archive_location=archive_location)
            if self.dicom_archive_obj.tarchive_info_dict:
                tarchive_id = self.dicom_archive_obj.tarchive_info_dict["TarchiveID"]
                success, new_err_msg = self.imaging_upload_obj.create_imaging_upload_dict_from_tarchive_id(tarchive_id)
                if not success:
                    err_msg += new_err_msg
            else:
                err_msg += f"Could not load tarchive dictionary for ArchiveLocation {archive_location}"

        if not success and not self.force:
            self.log_error_and_exit(err_msg, lib.exitcode.SELECT_FAILURE, is_error="Y", is_verbose="N")

    def determine_study_info(self):
        """
        Determine the study center associated to the DICOM archive based on a DICOM header
        specified by the lookupCenterNameUsing config setting.

        :return: dictionary with CenterName and CenterID information
         :rtype: dict
        """

        # get the CenterID from the session table if the PSCID and visit label exists
        # and could be extracted from the database
        self.session = try_get_session_with_cand_id_visit_label(
            self.db_orm,
            self.subject.cand_id,
            self.subject.visit_label,
        )

        if self.session is not None:
            return {"CenterName": self.session.site.mri_alias, "CenterID": self.session.site_id}

        # if could not find center information based on cand_id and visit_label, use the
        # patient name to match it to the site alias or MRI alias
        list_of_sites = self.session_obj.get_list_of_sites()
        for site_dict in list_of_sites:
            if site_dict["Alias"] in self.subject.name:
                return {"CenterName": site_dict["Alias"], "CenterID": site_dict["CenterID"]}
            elif site_dict["MRI_alias"] in self.subject.name:
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
        scanner_id = self.imaging_obj.get_scanner_id(
            self.dicom_archive_obj.tarchive_info_dict['ScannerManufacturer'],
            self.dicom_archive_obj.tarchive_info_dict['ScannerSoftwareVersion'],
            self.dicom_archive_obj.tarchive_info_dict['ScannerSerialNumber'],
            self.dicom_archive_obj.tarchive_info_dict['ScannerModel'],
            self.site_dict['CenterID'],
            self.session.project_id if self.session is not None else None,
        )
        message = f"Found Scanner ID: {str(scanner_id)}"
        self.log_info(message, is_error="N", is_verbose="Y")
        return scanner_id

    def validate_subject_ids(self):
        """
        Ensure that the subject PSCID/CandID corresponds to a single candidate in the candidate
        table and that the visit label can be found in the Visit_Windows table. If those
        conditions are not fulfilled.
        """

        try:
            validate_subject_ids(self.db_orm, self.subject)

            self.imaging_upload_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('1',)
            )
        except ValidateSubjectException as exception:
            self.log_info(exception.message, is_error='Y', is_verbose='N')
            self.imaging_upload_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('0',)
            )

    def log_error_and_exit(self, message, exit_code, is_error, is_verbose) -> Never:
        """
        Function to commonly executes all logging information when the script needs to be
        interrupted due to an error. It will log the error in the log file created by the
        script being executed, add an entry with the error in the notification_spool table
        and print the error to the user in the terminal.

        :param message: message to log before exit
         :type message: str
        :param exit_code: exit code to use to exit the script
         :type exit_code: int
        :param is_error: whether the message to log is an error or not
         :type is_error: str
        :param is_verbose: whether the message is considered verbose or not in the notification_spool table
         :type is_verbose: str
        """
        err_msg = f"[ERROR   ] {message}"
        self.log_obj.write_to_log_file(f"\n{err_msg}\n")
        self.log_obj.write_to_notification_table(err_msg, is_error, is_verbose)
        if self.upload_id:
            self.imaging_upload_obj.update_mri_upload(upload_id=self.upload_id, fields=("Inserting",), values=("0",))
        print(f"\n{err_msg}\n")
        self.remove_tmp_dir()
        sys.exit(exit_code)

    def log_info(self, message, is_error, is_verbose):
        """
        Function to log information that need to be logged in the notification_spool table and in the log
        file produced by the script executed.

        :param message: message to log
         :type message: str
        :param is_error: whether the message to log is an error or not
         :type is_error: str
        :param is_verbose: whether the message is considered verbose or not in the notification_spool table
         :type is_verbose: str
        """
        log_msg = f"==> {message}"
        self.log_obj.write_to_log_file(f"{log_msg}\n")
        self.log_obj.write_to_notification_table(log_msg, is_error, is_verbose)
        if self.verbose:
            print(f"{log_msg}\n")

    def check_if_tarchive_validated_in_db(self):
        """
        Checks whether the DICOM archive was previously validated in the database (as per the value present
        in the <IsTarchiveValidated> field of the <mri_upload> table.

        If the DICOM archive was not validated, the pipeline will exit and log the proper error information.
        """
        # reload the mri_upload object with updated database values
        self.load_imaging_upload_and_tarchive_dictionaries()
        mu_dict = self.imaging_upload_obj.imaging_upload_dict
        if ("IsTarchiveValidated" not in mu_dict.keys() or not mu_dict["IsTarchiveValidated"]) and not self.force:
            err_msg = f"The DICOM archive validation has failed for UploadID {self.upload_id}. Either run the" \
                      f" validation again and fix the problem or use --force to force the insertion of the NIfTI file."
            self.log_error_and_exit(err_msg, lib.exitcode.INVALID_DICOM, is_error="Y", is_verbose="N")

    def create_dir(self, directory_path):
        """
        Create a directory on the file system.

        :param directory_path: path of the directory to create
         :type directory_path: str
        """

        if not os.path.exists(directory_path):
            self.log_info(f'Creating directory {directory_path}', is_error='N', is_verbose='Y')
            os.makedirs(directory_path)
            if not os.path.exists(directory_path):
                message = f'Failed creating directory {directory_path}'
                self.log_error_and_exit(message, lib.exitcode.CREATE_DIR_FAILURE, is_error='Y', is_verbose='N')

    def move_file(self, old_file_path, new_file_path):
        """
        Move a file on the file system.

        :param old_file_path: where to move the file from
         :type old_file_path: str
        :param new_file_path: where to move the file to
         :type new_file_path: str
        """

        self.log_info(f'Moving {old_file_path} to {new_file_path}', is_error='N', is_verbose='Y')
        shutil.move(old_file_path, new_file_path)
        if not os.path.exists(new_file_path):
            message = f'Could not move {old_file_path} to {new_file_path}'
            self.log_error_and_exit(message, lib.exitcode.COPY_FAILURE, is_error='Y', is_verbose='N')

    def remove_tmp_dir(self):
        """
        Removes the temporary directory that was created by the pipeline.
        """

        if os.path.exists(self.tmp_dir):
            try:
                shutil.rmtree(self.tmp_dir)
            except PermissionError as err:
                self.log_info(f"Could not delete {self.tmp_dir}. Error was: {err}", "N", "Y")
