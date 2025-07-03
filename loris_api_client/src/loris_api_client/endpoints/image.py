from requests import HTTPError

from loris_api_client.client import LorisApiClient
from loris_api_client.models.image import GetImages


def try_get_candidate_images(api: LorisApiClient, candidate_id: str | int, visit_label: str) -> GetImages | None:
    try:
        return get_candidate_images(api, candidate_id, visit_label)
    except HTTPError as error:
        if error.response.status_code == 404:
            return None
        else:
            raise error


def get_candidate_images(api: LorisApiClient, candidate_id: str | int, visit_label: str) -> GetImages:
    response = api.get('v0.0.4-dev', f'candidates/{candidate_id}/{visit_label}/images')
    return GetImages.model_validate(response.json())
