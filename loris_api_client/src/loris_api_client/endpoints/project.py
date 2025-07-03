from requests import HTTPError

from loris_api_client.client import LorisApiClient
from loris_api_client.models.project import (
    GetProject,
    GetProjectCandidates,
    GetProjectImages,
    GetProjectInstruments,
    GetProjectRecordings,
    GetProjectVisits,
)


def try_get_project(api: LorisApiClient, project_name: str) -> GetProject | None:
    try:
        return get_project(api, project_name)
    except HTTPError as error:
        if error.response.status_code == 404:
            return None

        raise error


def get_project(api: LorisApiClient, project_name: str) -> GetProject:
    response = api.get('v0.0.4-dev', f'projects/{project_name}')
    return GetProject.model_validate(response.json())


def get_project_candidates(api: LorisApiClient, project_name: str) -> GetProjectCandidates:
    response = api.get('v0.0.4-dev', f'projects/{project_name}/candidates')
    return GetProjectCandidates.model_validate(response.json())


def get_project_images(api: LorisApiClient, project_name: str) -> GetProjectImages:
    response = api.get('v0.0.4-dev', f'projects/{project_name}/images')
    return GetProjectImages.model_validate(response.json())


def get_project_instruments(api: LorisApiClient, project_name: str) -> GetProjectInstruments:
    response = api.get('v0.0.4-dev', f'projects/{project_name}/instruments')
    return GetProjectInstruments.model_validate(response.json())


def get_project_visits(api: LorisApiClient, project_name: str) -> GetProjectVisits:
    response = api.get('v0.0.4-dev', f'projects/{project_name}/visits')
    return GetProjectVisits.model_validate(response.json())


def get_project_recordings(api: LorisApiClient, project_name: str) -> GetProjectRecordings:
    response = api.get('v0.0.4-dev', f'projects/{project_name}/recordings')
    return GetProjectRecordings.model_validate(response.json())
