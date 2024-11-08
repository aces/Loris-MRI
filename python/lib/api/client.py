from dataclasses import dataclass
from typing import Any, Literal

import requests
from requests import HTTPError

# TODO: Turn into a type declaration with Python 3.12
ApiVersion = Literal['v0.0.3', 'v0.0.4-dev']


@dataclass
class ApiClient:
    loris_url: str
    api_token: str

    def get(
        self,
        version: ApiVersion,
        route: str,
        json: dict[str, Any] | None = None,
    ):
        headers = {
            'Authorization': f'Bearer {self.api_token}',
        }

        print(f'https://{self.loris_url}/api/{version}/{route}')

        try:
            response = requests.get(
                f'https://{self.loris_url}/api/{version}/{route}',
                headers=headers,
                json=json,
            )

            response.raise_for_status()
            return response
        except HTTPError as error:
            # TODO: Better error handling
            print(error.response.text)
            exit(0)

    def post(
        self,
        version: ApiVersion,
        route: str,
        data: dict[str, str] = {},
        json: dict[str, Any] | None = None,
        files: dict[str, Any] | None = None,
    ):
        headers = {
            'Authorization': f'Bearer {self.api_token}',
        }

        try:
            response = requests.post(
                f'https://{self.loris_url}/api/{version}/{route}',
                headers=headers,
                data=data,
                json=json,
                files=files,
            )

            response.raise_for_status()
            return response
        except HTTPError as error:
            # TODO: Better error handling
            print(error.response.status_code)
            print(error.response.text)
            exit(0)


def get_api_token(loris_url: str, username: str, password: str) -> str:
    """
    Call the LORIS API to get an API token for a given LORIS user using this user's credentials.
    """

    credentials = {
        'username': username,
        'password': password,
    }

    try:
        response = requests.post(f'https://{loris_url}/api/v0.0.4-dev/login', json=credentials)
        response.raise_for_status()
        return response.json()['token']
    except HTTPError as error:
        error_description = error.response.json()['error']
        if error_description == 'Unacceptable JWT key':
            raise Exception(
                'Unacceptable LORIS JWT key.\n'
                'To use the API, please enter a sufficiently complex JWT key in the LORIS configuration module.'
            )

        exit(0)


def get_api_client(loris_url: str, username: str, password: str):
    api_token = get_api_token(loris_url, username, password)
    return ApiClient(loris_url, api_token)
