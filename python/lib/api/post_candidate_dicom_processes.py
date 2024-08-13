from lib.api import Api


def post_candidate_dicom_processes(api: Api, cand_id: int, visit_label: str, dicom_tar_name: str, upload_id: int):
    data = {
        'ProcessType': 'mri_upload',
        'MRIUploadID': upload_id,
    }

    api.call('v0.0.4-dev', f'/candidates/{cand_id}/{visit_label}/dicoms/{dicom_tar_name}/processes', method='POST', data=data)
    # TODO: Handle 202
