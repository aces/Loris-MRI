from lib.dataclass.api import Api


def post_candidate_dicom_processes(api: Api, cand_id: int, visit_label: str, dicom_tar_name: str, upload_id: int):
    json = {
        'ProcessType': 'mri_upload',
        'MRIUploadID': upload_id,
    }

    api.post(
        'v0.0.4-dev',
        f'/candidates/{cand_id}/{visit_label}/dicoms/{dicom_tar_name}/processes',
        json=json,
    )

    # TODO: Handle 202
