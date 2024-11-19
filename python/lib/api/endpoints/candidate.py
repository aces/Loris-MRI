from lib.api.client import ApiClient
from lib.api.models.candidate import GetCandidate


def get_candidate(api: ApiClient, id: int | str):
    response = api.get('v0.0.4-dev', f'candidates/{id}')
    return GetCandidate.model_validate(response.json())
