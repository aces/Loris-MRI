from dataclasses import dataclass
from json import dumps
from typing import Any, Literal
import requests
from requests.exceptions import HTTPError


@dataclass
class Api:
    """
    Class used to interact with the LORIS API, using the LORIS URL.
    """

    loris_url: str
    api_token: str

    @staticmethod
    def from_token(loris_url: str, api_token: str):
        """
        Create an API object from the LORIS URL and an API token, which will be used for all API
        calls made using this API object.
        """

        return Api(loris_url, api_token)

    @staticmethod
    def from_credentials(loris_url: str, username: str, password: str):
        """
        Create an API object from the LORIS URL and some user's credentials. This function calls
        the LORIS API to get the user's API token, which will be used for all other API calls made
        using this API object.
        """

        api_token = get_api_token(loris_url, username, password)
        return Api(loris_url, api_token)

    def get(
        self,
        version: Literal['v0.0.3', 'v0.0.4-dev'],
        route: str,
        headers: dict[str, str] = {},
        json: dict[str, Any] | None = None,
    ):
        """
        Generic method to call any LORIS API route. This method uses unstructured values as the
        parameter route and the return value. As such, it should not be used directly in a script
        but rather used into a wrapper for a specific route that structures both its arguments and
        return value.

        :param version: The version of the API to use for this call
        :param route:   The API route to call, example: `/candidates/123456`
        :param headers: Additional HTTP headers to add to the request
        :param data:    A body to add to the request
        """

        print(f'{self.loris_url}/api/{version}/{route}')

        headers['Authorization'] = f'Bearer {self.api_token}'

        try:
            response = requests.get(f'{self.loris_url}/api/{version}/{route}', headers=headers, json=json)
            response.raise_for_status()
            return response
        except HTTPError as error:
            # TODO: Better error handling
            print(error.response.text)
            exit(0)

    def post(
        self,
        version: Literal['v0.0.3', 'v0.0.4-dev'],
        route: str,
        headers: dict[str, str] = {},
        json: dict[str, Any] | None = None,
    ):
        """
        Generic method to call any LORIS API route. This method uses unstructured values as the
        parameter route and the return value. As such, it should not be used directly in a script
        but rather used into a wrapper for a specific route that structures both its arguments and
        return value.

        :param version: The version of the API to use for this call
        :param route:   The API route to call, example: `/candidates/123456`
        :param headers: Additional HTTP headers to add to the request
        :param data:    A body to add to the request
        """

        print(f'{self.loris_url}/api/{version}/{route}')

        headers['Authorization'] = f'Bearer {self.api_token}'

        try:
            response = requests.post(f'{self.loris_url}/api/{version}/{route}',headers=headers, json=json)
            print(response.status_code)
            print(response.text)
            response.raise_for_status()
            return response
        except HTTPError as error:
            # TODO: Better error handling
            print(error.response.status_code)
            print(error.response.text)
            exit(0)


    def post_file(
        self,
        version: Literal['v0.0.3', 'v0.0.4-dev'],
        route: str,
        headers: dict[str, str] = {},
        json: dict[str, Any] | None = None,
        files: dict[str, Any] | None = None,
    ):
        """
        Generic method to call any LORIS API route. This method uses unstructured values as the
        parameter route and the return value. As such, it should not be used directly in a script
        but rather used into a wrapper for a specific route that structures both its arguments and
        return value.

        :param version: The version of the API to use for this call
        :param route:   The API route to call, example: `/candidates/123456`
        :param headers: Additional HTTP headers to add to the request
        :param data:    A body to add to the request
        """

        headers['Authorization'] = f'Bearer {self.api_token}'

        # Since it is not possible to send both a file and a JSON directly in a multipart/form-data
        # POST request, we send the JSON as a form data attribute.
        data = { 'json': dumps(json) }

        try:
            response = requests.post(f'{self.loris_url}/api/{version}/{route}',headers=headers, data=data, files=files)
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
        response = requests.post(f'{loris_url}/api/v0.0.3/login', json=credentials)
        response.raise_for_status()
        return response.json()['token']
    except HTTPError as error:
        error_description = error.response.json()['error']
        if error_description == 'Unacceptable JWT key':
            # TODO: Specialized exception.
            raise Exception(
                'Unacceptable LORIS JWT key.\n'
                'To use the API, please enter a sufficiently complex JWT key in the LORIS configuration module.'
            )

        exit(0)
