from loris_api_client.client import LorisApiClient
from loris_api_client.models.dicom import GetDicom


def get_candidate_dicom(api: LorisApiClient, cand_id: int, visit_label: str) -> GetDicom:
    response = api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms')
    return GetDicom.model_validate(response.json())


def get_candidate_dicom_archive(api: LorisApiClient, cand_id: int, visit_label: str, tar_name: str):
    api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}/dicoms/{tar_name}')
    # TODO: Handle returned file
