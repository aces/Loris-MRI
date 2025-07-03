from requests import HTTPError

from loris_api_client.client import LorisApiClient
from loris_api_client.models.candidate import GetCandidate


def try_get_candidate(api: LorisApiClient, id: int | str) -> GetCandidate | None:
    try:
        return get_candidate(api, id)
    except HTTPError as error:
        if error.response.status_code == 404:
            return None
        else:
            raise error


def get_candidate(api: LorisApiClient, id: int | str) -> GetCandidate:
    response = api.get('v0.0.4-dev', f'candidates/{id}')
    return GetCandidate.model_validate(response.json())
