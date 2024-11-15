import json
import os

from requests_toolbelt import MultipartEncoder

from lib.api.client import ApiClient
from lib.api.models.dicom import GetDicom, GetDicomProcess, GetDicomProcesses, PostDicomProcesses


def get_candidate_dicom(api: ApiClient, cand_id: int, visit_label: str):
    response = api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms')
    return GetDicom.model_validate(response.json())


def post_candidate_dicom(
    api: ApiClient,
    cand_id: int,
    psc_id: str,
    visit_label: str,
    is_phantom: bool,
    overwrite: bool,
    file_path: str,
):
    multipart = MultipartEncoder(fields={
        'Json': json.dumps({
            'CandID': cand_id,
            'PSCID': psc_id,
            'VisitLabel': visit_label,
            'IsPhantom': is_phantom,
            'Overwrite': overwrite,
        }),
        'File': (os.path.basename(file_path), open(file_path, 'rb'), 'application/x-tar'),
    })

    response = api.post('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms', data=multipart)
    return response.headers['Location']


def get_candidate_dicom_archive(api: ApiClient, cand_id: int, visit_label: str, tar_name: str):
    api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms/{tar_name}')
    # TODO: Handle returned file


def get_candidate_dicom_processes(api: ApiClient, cand_id: int, visit_label: str, tar_name: str):
    response = api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms/{tar_name}/processes')
    return GetDicomProcesses.model_validate(response.json())


def post_candidate_dicom_processes(api: ApiClient, cand_id: int, visit_label: str, tar_name: str, upload_id: int):
    json = {
        'ProcessType': 'mri_upload',
        'MriUploadID': upload_id,
    }

    response = api.post(
        'v0.0.4-dev',
        f'/candidates/{cand_id}/{visit_label}/dicoms/{tar_name}/processes',
        json=json,
    )

    return PostDicomProcesses.model_validate(response.json())


def get_candidate_dicom_process(api: ApiClient, cand_id: int, visit_label: str, tar_name: str, process_id: int):
    response = api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms/{tar_name}/processes/{process_id}')
    return GetDicomProcess.model_validate(response.json())
