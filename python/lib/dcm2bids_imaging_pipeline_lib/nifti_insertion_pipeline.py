import hashlib
import json
import lib.exitcode
from lib.database_lib.files import Files
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from lib.imaging import Imaging
from pyblake2 import blake2b

__license__ = "GPLv3"


class NiftiInsertionPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.nifti_path = self.options_dict["nifti_path"]["value"]
        self.nifti_blake2 = blake2b(self.nifti_path.encode('utf-8')).hexdigest()
        self.nifti_md5 = hashlib.md5(self.nifti_path.encode()).hexdigest()
        self.json_path = self.options_dict["json_path"]["value"]
        self.json_blake2 = blake2b(self.json_path.encode('utf-8')).hexdigest()
        self.json_md5 = hashlib.md5(self.json_path.encode()).hexdigest()
        self.force = self.options_dict["force"]["value"]

        # ---------------------------------------------------------------------------------------------
        # Check the mri_upload table to see if the DICOM archive has been validated
        # ---------------------------------------------------------------------------------------------
        self.imaging_obj = Imaging(self.db, self.verbose, self.config_file)

        # ---------------------------------------------------------------------------------------------
        # Check the mri_upload table to see if the DICOM archive has been validated
        # ---------------------------------------------------------------------------------------------
        self._check_if_tarchive_validated_in_db()

        # ---------------------------------------------------------------------------------------------
        # Load the JSON file object with scan parameters if a JSON file was provided
        # ---------------------------------------------------------------------------------------------
        self.json_file_dict = self._load_json_sidecar_file()

        # ---------------------------------------------------------------------------------------------
        # Check that the PatientName in NIfTI and DICOMs are the same and then validate the Subject IDs
        # ---------------------------------------------------------------------------------------------
        self._validate_nifti_patient_name()
        self.validate_subject_ids()

        # ---------------------------------------------------------------------------------------------
        # Verify if the image/NIfTI file was not already registered into the database
        # ---------------------------------------------------------------------------------------------
        self._check_if_nifti_file_was_already_inserted()

        # TODO: plan
        # 7. load nifti and JSON file
        # 12. if file not associated to a tarchiveID or uploadID, check that cannot find it in tarchive tables.
        # If so, exits
        # 13. get more information about the scan (scanner, IDs, dates...)
        # 14. get session information, exits if incorrect
        # 15. check if file is unique
        # 16. determine acquisition protocol
        # 17. insert into Db
        # 18. update mri violations log
        # 19. create pics

    def _check_if_tarchive_validated_in_db(self):
        """
        Checks whether the DICOM archive was previously validated in the database (as per the value present
        in the <IsTarchiveValidated> field of the <mri_upload> table.

        If the DICOM archive was not validated, the pipeline will exit and log the proper error information.
        """
        is_tarchive_validated = self.mri_upload_db_obj.mri_upload_dict["IsTarchiveValidated"]
        if not is_tarchive_validated and not self.force:
            err_msg = f"The DICOM archive validation has failed for UploadID {self.upload_id}. Either run the" \
                      f" validation again and fix the problem or use --force to force the insertion of the NIfTI file."
            self.log_error_and_exit(err_msg, lib.exitcode.INVALID_DICOM, is_error="Y", is_verbose="N")

    def _load_json_sidecar_file(self):
        """
        Loads the JSON file content into a dictionary.

        Note: if no JSON file was provided to the pipeline, the function will return an empty dictionary
        so that information to be stored in <parameter_file> later on can be added to the JSON dictionary.

        :return: dictionary with the information present in the JSON file
         :rtype: dict
        """
        json_path = self.options_dict["json_path"]["value"]

        if not json_path:
            return dict()

        with open(json_path) as json_file:
            json_data_dict = json.load(json_file)
        # TODO might be best to move the mapping in SQL and instead insert in parameter file only the BIDS terms
        self.imaging_obj.map_bids_param_to_loris_param(json_data_dict)
        return json_data_dict

    def _validate_nifti_patient_name(self):
        """
        This function will validate that the PatientName present in the JSON side car file is the same as the
        one present in the <tarchive> table.

        Note: if no JSON file was provided to the script or if not "PatientName" was provided in the JSON file,
        the scripts will rely solely on the PatientName present in the <tarchive> table.
        """
        tarchive_pname = self.tarchive_db_obj.tarchive_info_dict["PatientName"]
        if "PatientName" not in self.json_file_dict:
            message = "PatientName not present in the JSON file or no JSON file provided along with" \
                      "the NIfTI file. Will rely on the PatientName stored in the DICOM files"
            self.log_info(message, is_error="N", is_verbose="Y")
            return

        nifti_pname = self.json_file_dict["PatientName"]
        if tarchive_pname != nifti_pname:
            err_msg = "PatientName in DICOM and NIfTI files differ."
            self.log_error_and_exit(err_msg, lib.exitcode.FILENAME_MISMATCH, is_error="Y", is_verbose="N")

    def _check_if_nifti_file_was_already_inserted(self):

        files_obj = Files(self.db, self.verbose)
        error_msg = None

        # verify that a file has not already be inserted with the same SeriesUID/EchoTime combination
        json_keys = self.json_file_dict.keys()
        if self.json_file_dict and "SeriesInstanceUID" in json_keys and "EchoTime" in json_keys:
            echo_time = self.json_file_dict["EchoTime"]
            series_uid = self.json_file_dict["SeriesInstanceUID"]
            match = files_obj.find_file_with_series_uid_and_echo_time(series_uid, echo_time)
            if match:
                error_msg = f"There is already a file registered in the files table with SeriesUID {series_uid} and" \
                            f" EchoTime {echo_time}. The already registered file is {match['File']}"

        # verify that a file with the same MD5 or blake2b hash has not already been inserted
        md5_match = files_obj.find_file_with_hash(self.nifti_md5)
        blake2b_match = files_obj.find_file_with_hash(self.nifti_blake2)
        if md5_match:
            error_msg = f"There is already a file registered in the files table with MD5 hash {self.nifti_md5}." \
                        f" The already registered file is {md5_match['File']}"
        elif blake2b_match:
            error_msg = f"There is already a file registered in the files table with Blake2b hash {self.nifti_blake2}." \
                        f" The already registered file is {blake2b_match['File']}"

        if error_msg:
            self.log_error_and_exit(error_msg, lib.exitcode.FILE_NOT_UNIQUE, is_error="Y", is_verbose="N")
