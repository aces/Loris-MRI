from dataclasses import dataclass
from typing import Any, Literal

import requests
from requests import Response

ApiVersion = Literal['v0.0.3', 'v0.0.4-dev']


@dataclass
class LorisApiClient:
    """
    LORIS API client object.
    """

    url: str
    """
    URL of the LORIS instance to which this client sends its requests.
    """

    username: str
    """
    Username of the LORIS API user.
    """

    token: str
    """
    API token used by the client.
    """

    @staticmethod
    def connect(loris_url: str, username: str, password: str) -> 'LorisApiClient':
        """
        Connect to the LORIS API using the provided URL, username, and password. Raise an exception
        if those parameters are incorrect.
        """

        api_token = get_loris_api_token(loris_url, username, password)
        return LorisApiClient(loris_url, username, api_token)

    def get(
        self,
        version: ApiVersion,
        route: str,
        json: dict[str, Any] | None = None,
    ) -> Response:
        """
        Sent a GET request to the LORIS API.
        """

        headers = {
            'Authorization': f'Bearer {self.token}',
        }

        response = requests.get(
            f'{self.url}/api/{version}/{route}',
            headers=headers,
            json=json,
            allow_redirects=False,
        )

        response.raise_for_status()
        return response

    def post(
        self,
        version: ApiVersion,
        route: str,
        data: dict[str, str] = {},
        json: dict[str, Any] | None = None,
        files: dict[str, Any] | None = None,
    ) -> Response:
        """
        Sent a POST request to the LORIS API.
        """

        headers = {
            'Authorization': f'Bearer {self.token}',
        }

        response = requests.post(
            f'{self.url}/api/{version}/{route}',
            headers=headers,
            data=data,
            json=json,
            files=files,
            allow_redirects=False,
        )

        response.raise_for_status()
        return response

    def put(
        self,
        version: ApiVersion,
        route: str,
        data: dict[str, str] = {},
        json: dict[str, Any] | None = None,
        files: dict[str, Any] | None = None,
    ) -> Response:
        """
        Sent a PUT request to the LORIS API.
        """

        headers = {
            'Authorization': f'Bearer {self.token}',
        }

        response = requests.put(
            f'{self.url}/api/{version}/{route}',
            headers=headers,
            data=data,
            json=json,
            files=files,
            allow_redirects=False,
        )

        response.raise_for_status()
        return response


def get_loris_api_token(loris_url: str, username: str, password: str) -> str:
    """
    Call the LORIS API to get an API token for a given LORIS user using this user's credentials.
    """

    credentials = {
        'username': username,
        'password': password,
    }

    response = requests.post(f'{loris_url}/api/v0.0.4-dev/login', json=credentials)
    response.raise_for_status()
    return response.json()['token']
