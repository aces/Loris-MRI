from dataclasses import dataclass
import json
from typing import Literal
from urllib.error import HTTPError
from urllib.request import Request, urlopen

@dataclass
class Api:
    """
    Class used to interact with the LORIS API, using the LORIS URL.
    """

    loris_url: str
    api_token: str

    @staticmethod
    def get_api_from_token(loris_url: str, api_token: str):
        """
        Create an API object from the LORIS URL and an API token, which will be used for all API
        calls made using this API object.
        """

        return Api(loris_url, api_token)

    @staticmethod
    def get_api_from_credentials(loris_url: str, username: str, password: str):
        """
        Create an API object from the LORIS URL and some user's credentials. This function calls
        the LORIS API to get the user's API token, which will be used for all other API calls made
        using this API object.
        """

        api_token = get_api_token(loris_url, username, password)
        return Api(loris_url, api_token)

    def call(
        self,
        version: Literal['v0.0.3', 'v0.0.4-dev'],
        route: str,
        method: Literal['GET', 'POST'] = 'GET',
        headers: dict[str, str] = {},
        data: bytes | None = None
    ):
        """
        Generic method to call any LORIS API route. This method uses unstructured values as the
        parameter route and the return value. As such, it should not be used directly in a script
        but rather used into a wrapper for a specific route that structures both its arguments and
        return value.

        :param version: The version of the API to use for this call
        :param route:   The API route to call, example: `/candidates/123456`
        :param method:  The HTTP method to use for the request
        :param headers: Additional HTTP headers to add to the request
        :param data:    A body to add to the request
        """

        print(f'{self.loris_url}/api/{version}/{route}')

        request = Request(f'{self.loris_url}/api/{version}/{route}', data, method=method)
        request.add_header('Authorization', f'Bearer {self.api_token}')
        for key, value in headers.items():
            request.add_header(key, value)

        try:
            return urlopen(request, data)
        except HTTPError as error:
            # TODO: Better error handling
            print(error.read())
            exit(0)


def get_api_token(loris_url: str, username: str, password: str) -> str:
    """
    Call the LORIS API to get an API token for a given LORIS user using this user's credentials.
    """

    credentials = {
        'username': username,
        'password': password,
    }

    request = Request(
        f'{loris_url}/api/v0.0.3/login',
        method='POST',
        data=json.dumps(credentials).encode('utf-8')
    )

    try:
        response = urlopen(request).read()
    except HTTPError as error:
        error_description = json.loads(error.read().decode('utf-8'))['error']
        if error_description == 'Unacceptable JWT key':
            # TODO: Specialzied exception.
            raise Exception(
                'Unacceptable LORIS JWT key.\n'
                'To use the API, please enter a sufficiently complex JWT key in the LORIS configuration module.'
            )

        exit(0)
    object = json.loads(response)
    return object['token']
