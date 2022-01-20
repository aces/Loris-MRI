import os
import sys

import lib.exitcode
import lib.utilities
from lib.aws_s3 import AwsS3
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
        # Get Bucket information from Config and connect to bucket
        # ---------------------------------------------------------------------------------------------
        self.s3_obj = AwsS3(
            aws_access_key_id=self.config_file.s3["aws_access_key_id"],
            aws_secret_access_key=self.config_file.s3["aws_secret_access_key"],
            aws_endpoint_url=self.config_file.s3["aws_s3_endpoint_url"],
            bucket_name=self.config_file.s3["aws_s3_bucket_name"]
        )

        # ---------------------------------------------------------------------------------------------
        # Get all the files from files, parameter_file and violation tables
        # ---------------------------------------------------------------------------------------------
        self.files_to_push_list = []
        self._get_files_to_push_list()

        # ---------------------------------------------------------------------------------------------
        # Upload files to S3
        # ---------------------------------------------------------------------------------------------
        self._upload_files_to_s3()

        # ---------------------------------------------------------------------------------------------
        # Update table file paths and delete file from file system
        # ---------------------------------------------------------------------------------------------
        for file_info in self.files_to_push_list:
            rel_path = file_info["original_file_path_field_value"]
            if self.s3_obj.check_if_file_key_exists_in_bucket(rel_path):
                self._update_database_tables_with_s3_path(file_info)
                print(f"DELETING s3_key")
                os.remove(os.path.join(self.data_dir, rel_path))

        self._clean_up_empty_folders()
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
                "original_file_path_field_value": file["File"]
            })

    def _get_list_of_files_from_parameter_file(self):

        file_ids = [v["id_field_value"] for v in self.files_to_push_list] if self.files_to_push_list else []

        files_info = []
        for file_id in file_ids:
            files_info.extend(self.imaging_obj.get_bids_files_info_from_parameter_file_for_file_id(file_id))
            pic_entry_dict = self.imaging_obj.grep_parameter_value_from_file_id_and_parameter_name(
                file_id, "check_pic_filename"
            )
            if pic_entry_dict:
                # for the pic, we need to add the pic/ subdir to the Value
                # otherwise, it will not be found on the filesystem
                pic_entry_dict["Value"] = "pic/" + pic_entry_dict["Value"]

            files_info.extend([pic_entry_dict])

        for file_entry in files_info:
            if not file_entry:
                continue
            self.files_to_push_list.append({
                "table_name": "parameter_file",
                "id_field_name": "ParameterFileID",
                "id_field_value": file_entry["ParameterFileID"],
                "file_path_field_name": "Value",
                "original_file_path_field_value": file_entry["Value"]
            })

    def _get_list_of_files_from_mri_protocol_violated_scans(self):

        entries = self.imaging_obj.mri_prot_viol_scan_db_obj.get_protocol_violations_for_tarchive_id(self.tarchive_id)

        for entry in entries:
            self.files_to_push_list.append({
                "table_name": "mri_protocol_violated_scans",
                "id_field_name": "ID",
                "id_field_value": entry["ID"],
                "file_path_field_name": "minc_location",
                "original_file_path_field_value": entry["minc_location"]
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
                "original_file_path_field_value": entry["MincFile"]
            })

    def _upload_files_to_s3(self):

        for file in self.files_to_push_list:
            file_full_path = os.path.join(self.data_dir, file["original_file_path_field_value"])
            s3_path = file["original_file_path_field_value"]
            file["s3_link"] = "/".join(["s3://", self.s3_obj.bucket_name, s3_path])

            self.s3_obj.upload_file(file_full_path, s3_path)

    def _update_database_tables_with_s3_path(self, file_info):

        table_name = file_info["table_name"]
        entry_id = file_info["id_field_value"]
        s3_link = file_info["s3_link"]
        field_to_update = file_info["file_path_field_name"]

        if table_name == "parameter_file":
            print(f"UPDATING TABLE {table_name} with link {s3_link}")
            self.imaging_obj.param_file_db_obj.update_parameter_file(s3_link, entry_id)
        elif table_name == "files":
            self.imaging_obj.files_db_obj.update_files(entry_id, (field_to_update,), (s3_link,))
        elif table_name == "mri_protocol_violated_scans":
            self.imaging_obj.mri_prot_viol_scan_db_obj.update_protocol_violated_scans(
                entry_id, (field_to_update,), (s3_link,)
            )
        elif table_name == "mri_violations_log":
            self.imaging_obj.mri_viol_log_db_obj.update_violations_log(entry_id, (field_to_update,), (s3_link,))

    def _clean_up_empty_folders(self):

        # remove empty folders from file system
        print(f"removing empty folders")
        cand_id = self.subject_id_dict["CandID"]
        bids_cand_id = f"sub-{cand_id}"
        print(os.path.join(self.data_dir, "assembly_bids", bids_cand_id))
        lib.utilities.remove_empty_folders(os.path.join(self.data_dir, "assembly_bids", bids_cand_id))
        lib.utilities.remove_empty_folders(os.path.join(self.data_dir, "pic", cand_id))
        lib.utilities.remove_empty_folders(os.path.join(self.data_dir, "trashbin"))
