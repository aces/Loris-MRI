import datetime
import json
import os
import re
import subprocess
import sys

import lib.exitcode
import lib.utilities
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline

__license__ = "GPLv3"


class PushImagingFilesToS3Pipeline(BasePipeline):
    """
    Pipeline that extends the BasePipeline class and pushes the data onto an S3 bucket, change the path locations
    to the S3 URLs and remove the files on the filesystem once done.

    Functions that starts with _ are functions specific to the PushToS3Pipeline class.
    """

    def __init__(self, loris_getopt_obj, script_name):
        """
        Initiate the PushImagingFilesToS3Pipeline class and runs the different steps required to push the data to S3 and
        update the file paths in the database.

        :param loris_getopt_obj: the LorisGetOpt object with getopt values provided to the pipeline
         :type loris_getopt_obj: LorisGetOpt obj
        :param script_name: name of the script calling this class
         :type script_name: str
        """

        super().__init__(loris_getopt_obj, script_name)
        self.tarchive_id = self.dicom_archive_obj.tarchive_info_dict["TarchiveID"]

        # ---------------------------------------------------------------------------------------------
        # Get all the files from files, parameter_file and violation tables
        # ---------------------------------------------------------------------------------------------
        self.files_to_push_list = []
        self._get_files_to_push_list()

        # ---------------------------------------------------------------------------------------------
        # Get Bucket information from Config
        # ---------------------------------------------------------------------------------------------

        # ---------------------------------------------------------------------------------------------
        # Upload files to S3
        # ---------------------------------------------------------------------------------------------

        # ---------------------------------------------------------------------------------------------
        # Get final S3 URL
        # ---------------------------------------------------------------------------------------------

        # ---------------------------------------------------------------------------------------------
        # Update table file paths
        # ---------------------------------------------------------------------------------------------

        # ---------------------------------------------------------------------------------------------
        # Delete file from the file system after having checked they are indeed on S3
        # ---------------------------------------------------------------------------------------------

        sys.exit(lib.exitcode.SUCCESS)

    def _get_files_to_push_list(self):

        # Get files in the files table
        self._get_list_of_files_from_files()

        # Get files in the parameter_file table
        self._get_list_of_files_from_parameter_file()

        # Get list of files in mri_protocol_violated_scans table
        self._get_list_of_files_from_mri_protocol_violated_scans()

        # Get list of files in mri_violations_log
        self._get_list_of_files_from_mri_violations_log()

    def _get_list_of_files_from_files(self):

        file_entries = self.imaging_obj.files_db_obj.get_files_inserted_for_tarchive_id(self.tarchive_id)
        for file in file_entries:
            self.files_to_push_list.append({
                "table_name": "files",
                "id_field_name": "FileID",
                "id_field_value": file["FileID"],
                "file_path_field_name": "File",
                "file_path_field_value": file["File"]
            })

    def _get_list_of_files_from_parameter_file(self):

        file_ids = [v["id_field_value"] for v in self.files_to_push_list] if self.files_to_push_list else []

        files_info = []
        for file_id in file_ids:
            files_info.extend(self.imaging_obj.get_bids_files_info_from_parameter_file_for_file_id(file_id))

        for file_entry in files_info:
            if not file_entry:
                continue
            self.files_to_push_list.append({
                "table_name": "parameter_file",
                "id_field_name": "ParameterFileID",
                "id_field_value": file_entry["ParameterFileID"],
                "file_path_field_name": "Value",
                "file_path_field_value": file_entry["Value"]
            })

    def _get_list_of_files_from_mri_protocol_violated_scans(self):

        entries = self.imaging_obj.mri_prot_viol_scan_db_obj.get_protocol_violations_for_tarchive_id(self.tarchive_id)

        for entry in entries:
            self.files_to_push_list.append({
                "table_name": "mri_protocol_violated_scans",
                "id_field_name": "ID",
                "id_field_value": entry["ID"],
                "file_path_field_name": "minc_location",
                "file_path_field_value": entry["minc_location"]
            })

    def _get_list_of_files_from_mri_violations_log(self):

        exclude_entries = self.imaging_obj.mri_viol_log_db_obj.get_excluded_violations_for_tarchive_id(
            self.tarchive_id, "exclude"
        )
        warning_entries = self.imaging_obj.mri_viol_log_db_obj.get_excluded_violations_for_tarchive_id(
            self.tarchive_id, "warning"
        )

        for entry in exclude_entries + warning_entries:
            self.files_to_push_list.append({
                "table_name": "mri_violations_log",
                "id_field_name": "LogID",
                "id_field_value": entry["LogID"],
                "file_path_field_name": "MincFile",
                "file_path_field_value": entry["MincFile"]
            })
