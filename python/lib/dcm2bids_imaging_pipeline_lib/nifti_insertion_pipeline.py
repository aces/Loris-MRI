import json
import lib.exitcode
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from lib.imaging import Imaging

__license__ = "GPLv3"


class NiftiInsertionPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.nifti_path = self.options_dict["nifti_path"]["value"]
        self.json_path = self.options_dict["json_path"]["value"]
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

        print("hello")

    def _check_if_tarchive_validated_in_db(self):

        is_tarchive_validated = self.mri_upload_db_obj.mri_upload_dict["IsTarchiveValidated"]
        if not is_tarchive_validated and not self.force:
            err_msg = f"The DICOM archive validation has failed for UploadID {self.upload_id}. Either run the" \
                      f" validation again and fix the problem or use --force to force the insertion of the NIfTI file."
            self.log_error_and_exit(err_msg, lib.exitcode.INVALID_DICOM, is_error="Y", is_verbose="N")

    def _load_json_sidecar_file(self):
        json_path = self.options_dict["json_path"]["value"]

        if not json_path:
            return None

        with open(json_path) as json_file:
            json_data_dict = json.load(json_file)
        # TODO might be best to move the mapping in SQL and instead insert in parameter file only the BIDS terms
        self.imaging_obj.map_bids_param_to_loris_param(json_data_dict)
        return json_data_dict

    def _validate_nifti_patient_name(self):
        tarchive_pname = self.tarchive_db_obj.tarchive_info_dict["PatientName"]
        nifti_pname = self.json_file_dict["PatientName"]

        if tarchive_pname != nifti_pname:
            err_msg = "PatientName in DICOM and NIfTI files differ."
            self.log_error_and_exit(err_msg, lib.exitcode.FILENAME_MISMATCH, is_error="Y", is_verbose="N")

