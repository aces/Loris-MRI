from dataclasses import dataclass
import json
from typing import Literal
from urllib.request import Request, urlopen


@dataclass
class Api:
    """
    Class used to interact with the LORIS API.
    """

    loris_url: str
    api_token: str

    @staticmethod
    def get_api_from_token(loris_url: str, api_token: str):
        """
        Create an API object from the LORIS URL and an API token.
        """

        return Api(loris_url, api_token)

    @staticmethod
    def get_api_from_credentials(loris_url: str, username: str, password: str):
        """
        Create an API object from the LORIS URL and an API token. This function
        calls the LORIS API using the credentials it is provided with.
        """

        api_token = get_api_token(loris_url, username, password)
        return Api(loris_url, api_token)

    def call(
        self,
        version: Literal['v0.0.3', 'v0.0.4-dev'],
        route: str,
        method: Literal['GET', 'POST'] = 'GET',
        headers: dict[str, str] = {},
        data: bytes = None
    ):
        """
        Generic method to call any LORIS API route. This method uses unstructured values as the
        parameter route and the return value. As such, it should not be used directly in a script
        but rather used into a wrapper for a specific route that structures both its arguments and
        return value.
        """

        request = Request(f'{self.loris_url}/api/{version}/{route}', data, method=method)
        request.add_header('Authorization', f'Bearer {self.api_token}')
        for key, value in headers.items():
            request.add_header(key, value)

        return urlopen(request, data)


def get_api_token(loris_url: str, username: str, password: str) -> str:
    """
    Call the LORIS API to get an API token for a given user using this user's credentials.
    """

    args = {
        'username': username,
        'password': password,
    }

    request = Request(
        f'{loris_url}/api/v0.0.3/login',
        method='POST',
        data=json.dumps(args)
    )

    response = urlopen(request).read()
    object = json.loads(response)
    return object['token']
