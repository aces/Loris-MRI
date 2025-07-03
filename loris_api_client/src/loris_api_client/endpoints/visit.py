from requests import HTTPError

from loris_api_client.client import LorisApiClient
from loris_api_client.models.visit import GetVisit


def try_get_candidate_visit(api: LorisApiClient, cand_id: int, visit_label: str) -> GetVisit | None:
    try:
        return get_candidate_visit(api, cand_id, visit_label)
    except HTTPError as error:
        if error.response.status_code == 404:
            return None
        else:
            raise error


def get_candidate_visit(api: LorisApiClient, cand_id: int, visit_label: str) -> GetVisit:
    response = api.get('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}')
    return GetVisit.model_validate(response.json())


def create_candidate_visit(
    api: LorisApiClient,
    cand_id: int,
    visit_label: str,
    site_name: str,
    project_name: str,
    cohort_name: str,
):
    try:
        api.put('v0.0.4-dev', f'candidates/{cand_id}/{visit_label}', json={
            'CandID': str(cand_id),
            'Visit': visit_label,
            'Site': site_name,
            'Cohort': cohort_name,
            'Project': project_name,
        })
    except HTTPError as error:
        print(error.response.text)
        raise error
