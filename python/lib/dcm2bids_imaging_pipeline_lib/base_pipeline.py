import os
import shutil

import lib.exitcode
import lib.utilities
from lib.config import get_data_dir_path_config, get_dicom_archive_dir_path_config
from lib.database import Database
from lib.db.queries.dicom_archive import try_get_dicom_archive_with_archive_location
from lib.db.queries.mri_upload import try_get_mri_upload_with_id
from lib.get_session_info import SessionConfigError, get_dicom_archive_session_info
from lib.imaging import Imaging
from lib.logging import log_error_exit, log_verbose, log_warning
from lib.make_env import make_env


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
        - load the Config, Imaging and other classes
        - creates the processing temporary directory
        - creates the log file for the script execution
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

        # ----------------------------------------------------
        # Establish database connection
        # ----------------------------------------------------
        self.db = Database(self.config_file.mysql, self.verbose)
        self.db.connect()

        # -----------------------------------------------------------------------------------
        # Load the Imaging database class
        # -----------------------------------------------------------------------------------
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)

        # ---------------------------------------------------------------------------------------------
        # Create tmp dir and log file (their basename being the name of the script run)
        # ---------------------------------------------------------------------------------------------
        self.tmp_dir = self.loris_getopt_obj.tmp_dir
        self.env = make_env(self.loris_getopt_obj)
        self.env.add_cleanup(self.remove_tmp_dir)

        # ---------------------------------------------------------------------------------------------
        # Grep config settings from the config module
        # ---------------------------------------------------------------------------------------------
        self.data_dir = get_data_dir_path_config(self.env)
        self.dicom_lib_dir = get_dicom_archive_dir_path_config(self.env)

        # ---------------------------------------------------------------------------------------------
        # Load imaging_upload and tarchive dictionary
        # ---------------------------------------------------------------------------------------------
        self.load_mri_upload_and_dicom_archive()

        # ---------------------------------------------------------------------------------------------
        # Set Inserting field of mri_upload to indicate a script is running on the upload
        # and load the notification object
        # ---------------------------------------------------------------------------------------------
        # Update the MRI upload.
        self.mri_upload.inserting = True
        self.env.db.commit()

        self.env.add_cleanup(self.end_upload)
        self.env.init_notifier(self.mri_upload.id)

    def init_session_info(self):
        """
        Get the session information and assign `self.session` and `self.scanner` for this pipeline.
        """

        try:
            session_info = get_dicom_archive_session_info(self.env, self.dicom_archive)

            self.session     = session_info.session
            self.mri_scanner = session_info.scanner

            # Update the MRI upload.
            self.mri_upload.is_candidate_info_validated = True
            self.env.db.commit()

            log_verbose(self.env, (
                f"Found Center Name: {self.session.site.name},"
                f" Center ID: {self.session.site.id}"
            ))

            log_verbose(self.env, f"Found scanner ID: {self.mri_scanner.id}")
        except SessionConfigError as error:
            log_warning(self.env, str(error))

            self.session     = None
            self.mri_scanner = None

            # Update the MRI upload.
            self.mri_upload.is_candidate_info_validated = False
            self.env.db.commit()

    def load_mri_upload_and_dicom_archive(self):
        """
        Loads the MRI upload and DICOM archives based on the content of the imaging_upload
        and tarchive tables found for the processed UploadID/ArchiveLocation given as argument to
        the script.
        """

        upload_id = self.options_dict["upload_id"]["value"]
        tarchive_path = self.options_dict["tarchive_path"]["value"] \
            if "tarchive_path" in self.options_dict.keys() else None

        if upload_id and tarchive_path:
            mri_upload = try_get_mri_upload_with_id(self.env.db, upload_id)
            if mri_upload is None:
                log_error_exit(
                    self.env,
                    f"Did not find an entry in mri_upload associated with \'UploadID\' {upload_id}.",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.mri_upload = mri_upload

            if self.mri_upload.dicom_archive is None:
                log_error_exit(
                    self.env,
                    f"UploadID {upload_id} is not linked to any tarchive in mri_upload.",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.dicom_archive = self.mri_upload.dicom_archive
            if os.path.join(self.data_dir, 'tarchive', self.dicom_archive.archive_location) != tarchive_path:
                log_error_exit(
                    self.env,
                    f"UploadID {upload_id} and ArchiveLocation {tarchive_path} do not refer to the same upload",
                    lib.exitcode.SELECT_FAILURE,
                )

        if upload_id:
            mri_upload = try_get_mri_upload_with_id(self.env.db, upload_id)
            if mri_upload is None:
                log_error_exit(
                    self.env,
                    f"Did not find an entry in mri_upload associated with 'UploadID' {upload_id}",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.mri_upload = mri_upload
            if self.mri_upload.dicom_archive is None:
                log_error_exit(
                    self.env,
                    f"Did not find a DICOM archive associated with upload ID {upload_id}",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.dicom_archive = self.mri_upload.dicom_archive

        elif tarchive_path:
            archive_location = tarchive_path.replace(self.dicom_lib_dir, "")
            dicom_archive = try_get_dicom_archive_with_archive_location(self.env.db, archive_location)
            if dicom_archive is None:
                log_error_exit(
                    self.env,
                    f"Could not load tarchive dictionary for ArchiveLocation {archive_location}",
                    lib.exitcode.SELECT_FAILURE,
                )

            self.dicom_archive = dicom_archive

            mri_uploads = self.dicom_archive.mri_uploads
            match mri_uploads:
                case []:
                    log_error_exit(
                        self.env,
                        f"Did not find an entry in mri_upload associated with DICOM archive ID {self.dicom_archive.id}",
                        lib.exitcode.SELECT_FAILURE,
                    )
                case [mri_upload]:
                    self.mri_upload = mri_upload
                case _:
                    log_error_exit(
                        self.env,
                        (
                            f"Found {len(mri_uploads)} rows in mri_upload for DICOM archive ID {self.dicom_archive.id}."
                            f" MRI upload IDs are {', '.join(map(lambda mri_upload: str(mri_upload.id), mri_uploads))}."
                        ),
                        lib.exitcode.SELECT_FAILURE,
                    )

    def check_if_tarchive_validated_in_db(self):
        """
        Checks whether the DICOM archive was previously validated in the database (as per the value present
        in the <IsTarchiveValidated> field of the <mri_upload> table.

        If the DICOM archive was not validated, the pipeline will exit and log the proper error information.
        """
        # reload the mri_upload object with updated database values
        self.load_mri_upload_and_dicom_archive()

        if not self.mri_upload.is_dicom_archive_validated and not self.force:
            log_error_exit(
                self.env,
                (
                    f"The DICOM archive validation has failed for UploadID {self.mri_upload.id}. Either run the"
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
        # Update the MRI upload.
        self.mri_upload.inserting = False
        self.env.db.commit()

    def remove_tmp_dir(self):
        """
        Removes the temporary directory that was created by the pipeline.
        """

        if os.path.exists(self.tmp_dir):
            try:
                shutil.rmtree(self.tmp_dir)
            except PermissionError as err:
                log_verbose(self.env, f"Could not delete {self.tmp_dir}. Error was: {err}")
