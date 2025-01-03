import os
import shutil

import lib.exitcode
import lib.utilities
from lib.database import Database
from lib.database_lib.config import Config
from lib.db.queries.dicom_archive import try_get_dicom_archive_with_archive_location, try_get_dicom_archive_with_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.site import get_all_sites
from lib.exception.determine_subject_info_error import DetermineSubjectInfoError
from lib.exception.validate_subject_info_error import ValidateSubjectInfoError
from lib.imaging import Imaging
from lib.imaging_upload import ImagingUpload
from lib.logging import log_error_exit, log_verbose, log_warning
from lib.make_env import make_env
from lib.validate_subject_info import validate_subject_info


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

        # -----------------------------------------------------------------------------------
        # Load the Config, Imaging, ImagingUpload, Tarchive, Session database classes
        # -----------------------------------------------------------------------------------
        self.config_db_obj = Config(self.db, self.verbose)
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)
        self.imaging_upload_obj = ImagingUpload(self.db, self.verbose)

        # ---------------------------------------------------------------------------------------------
        # Grep config settings from the Config module
        # ---------------------------------------------------------------------------------------------
        self.data_dir = self.config_db_obj.get_config("dataDirBasepath")
        self.dicom_lib_dir = self.config_db_obj.get_config('tarchiveLibraryDir')

        # ---------------------------------------------------------------------------------------------
        # Create tmp dir and log file (their basename being the name of the script run)
        # ---------------------------------------------------------------------------------------------
        self.tmp_dir = self.loris_getopt_obj.tmp_dir
        self.env = make_env(self.loris_getopt_obj)
        self.env.add_cleanup(self.remove_tmp_dir)
        self.env.add_cleanup(self.end_upload)

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
            self.env.init_notifier(self.upload_id)

        # ---------------------------------------------------------------------------------
        # Determine subject IDs based on DICOM headers and validate the IDs against the DB
        # Verify PSC information stored in DICOMs
        # Grep scanner information based on what is in the DICOM headers
        # ---------------------------------------------------------------------------------
        if self.dicom_archive is not None:
            try:
                self.subject_info = self.imaging_obj.determine_subject_info(self.dicom_archive)
            except DetermineSubjectInfoError as error:
                log_error_exit(self.env, error.message, lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE)

            # verify PSC information stored in DICOMs
            self.site_dict = self.determine_study_info()
            log_verbose(self.env, (
                f"Found Center Name: {self.site_dict['CenterName']},"
                f" Center ID: {self.site_dict['CenterID']}"
            ))

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
        if upload_id and tarchive_path:
            self.imaging_upload_obj.create_imaging_upload_dict_from_upload_id(upload_id)
            if not self.imaging_upload_obj.imaging_upload_dict:
                log_error_exit(
                    self.env,
                    f"Did not find an entry in mri_upload associated with \'UploadID\' {upload_id}.",
                    lib.exitcode.SELECT_FAILURE,
                )
            tarchive_id = self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]
            if not tarchive_id:
                log_error_exit(
                    self.env,
                    f"UploadID {upload_id} is not linked to any tarchive in mri_upload.",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.dicom_archive = try_get_dicom_archive_with_id(self.env.db, tarchive_id)
            if os.path.join(self.data_dir, 'tarchive', self.dicom_archive.archive_location) != tarchive_path:
                log_error_exit(
                    self.env,
                    f"UploadID {upload_id} and ArchiveLocation {tarchive_path} do not refer to the same upload",
                    lib.exitcode.SELECT_FAILURE,
                )

        err_msg = ''
        if upload_id:
            self.imaging_upload_obj.create_imaging_upload_dict_from_upload_id(upload_id)
            if not self.imaging_upload_obj.imaging_upload_dict:
                err_msg += f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}"
            else:
                if self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]:
                    tarchive_id = self.imaging_upload_obj.imaging_upload_dict["TarchiveID"]
                    self.dicom_archive = try_get_dicom_archive_with_id(self.env.db, tarchive_id)
                    if self.dicom_archive is not None:
                        success = True
                    else:
                        err_msg += f"Could not load tarchive dictionary for TarchiveID {tarchive_id}"

        elif tarchive_path:
            archive_location = tarchive_path.replace(self.dicom_lib_dir, "")
            self.dicom_archive = try_get_dicom_archive_with_archive_location(self.env.db, archive_location)
            if self.dicom_archive is not None:
                success, new_err_msg = self.imaging_upload_obj.create_imaging_upload_dict_from_tarchive_id(
                    self.dicom_archive.id
                )

                if not success:
                    err_msg += new_err_msg
            else:
                err_msg += f"Could not load tarchive dictionary for ArchiveLocation {archive_location}"

        if not success and not self.force:
            log_error_exit(self.env, err_msg, lib.exitcode.SELECT_FAILURE)

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
            self.env.db,
            self.subject_info.cand_id,
            self.subject_info.visit_label,
        )

        if self.session is not None:
            return {"CenterName": self.session.site.mri_alias, "CenterID": self.session.site_id}

        # if could not find center information based on cand_id and visit_label, use the
        # patient name to match it to the site alias or MRI alias
        sites = get_all_sites(self.env.db)
        for site in sites:
            if site.alias in self.subject_info.name:
                return {"CenterName": site.alias, "CenterID": site.id}
            elif site.mri_alias in self.subject_info.name:
                return {"CenterName": site.mri_alias, "CenterID": site.id}

        # if we got here, it means we could not find a center associated to the dataset
        log_error_exit(
            self.env,
            "No center found for this DICOM study",
            lib.exitcode.SELECT_FAILURE,
        )

    def determine_scanner_info(self):
        """
        Determine the scanner information found in the database for the uploaded DICOM archive.
        """
        scanner_id = self.imaging_obj.get_scanner_id(
            self.dicom_archive.scanner_manufacturer,
            self.dicom_archive.scanner_software_version,
            self.dicom_archive.scanner_serial_number,
            self.dicom_archive.scanner_model,
            self.site_dict['CenterID'],
            self.session.project_id if self.session is not None else None,
        )

        log_verbose(self.env, f"Found Scanner ID: {scanner_id}")
        return scanner_id

    def validate_subject_info(self):
        """
        Ensure that the subject PSCID/CandID corresponds to a single candidate in the candidate
        table and that the visit label can be found in the Visit_Windows table. If those
        conditions are not fulfilled.
        """

        try:
            validate_subject_info(self.env.db, self.subject_info)

            self.imaging_upload_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('1',)
            )
        except ValidateSubjectInfoError as error:
            log_warning(self.env, error.message)
            self.imaging_upload_obj.update_mri_upload(
                upload_id=self.upload_id, fields=('IsCandidateInfoValidated',), values=('0',)
            )

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
            log_error_exit(
                self.env,
                (
                    f"The DICOM archive validation has failed for UploadID {self.upload_id}. Either run the"
                    f" validation again and fix the problem or use --force to force the insertion of the NIfTI file."
                ),
                lib.exitcode.INVALID_DICOM,
            )

    def create_dir(self, directory_path):
        """
        Create a directory on the file system.

        :param directory_path: path of the directory to create
         :type directory_path: str
        """

        if not os.path.exists(directory_path):
            log_verbose(self.env, f"Creating directory {directory_path}")
            os.makedirs(directory_path)
            if not os.path.exists(directory_path):
                log_error_exit(
                    self.env,
                    f"Failed creating directory {directory_path}",
                    lib.exitcode.CREATE_DIR_FAILURE,
                )

    def move_file(self, old_file_path, new_file_path):
        """
        Move a file on the file system.

        :param old_file_path: where to move the file from
         :type old_file_path: str
        :param new_file_path: where to move the file to
         :type new_file_path: str
        """

        log_verbose(self.env, f"Moving {old_file_path} to {new_file_path}")
        shutil.move(old_file_path, new_file_path)
        if not os.path.exists(new_file_path):
            log_error_exit(
                self.env,
                f"Could not move {old_file_path} to {new_file_path}",
                lib.exitcode.COPY_FAILURE,
            )

    def end_upload(self):
        if self.upload_id:
            self.imaging_upload_obj.update_mri_upload(upload_id=self.upload_id, fields=("Inserting",), values=("0",))

    def remove_tmp_dir(self):
        """
        Removes the temporary directory that was created by the pipeline.
        """

        if os.path.exists(self.tmp_dir):
            try:
                shutil.rmtree(self.tmp_dir)
            except PermissionError as err:
                log_verbose(self.env, f"Could not delete {self.tmp_dir}. Error was: {err}")
