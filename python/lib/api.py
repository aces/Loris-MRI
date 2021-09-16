"""Allows LORIS API connectivity for LORIS-MRI python code base"""

import requests
import json
import urllib

__license__ = "GPLv3"


class Api:
    """
    This class performs common tasks related to the api connectivity between
    the LORIS-MRI python code base and the LORIS backend.
    """

    def __init__(self, verbose):
        """
        Constructor method for the Api class.

        :param verbose    : whether to be verbose or not
         :type verbose    : bool
        """

        self.verbose = verbose

        config = __import__('api_config').config

        # grep config settings from the Config module
        self.url = config['host'] + '/api/' + config['version'] + '/'
        self.username = config['username']
        self.password = config['password']

        self.login()

    def login(self):
        resp = requests.post(
            url=self.url + 'login',
            json={
                'username': self.username,
                'password': self.password
            },
            verify=False
        )

        try:
            resp_json = json.loads(resp.content.decode('ascii'))
            if resp_json.get('error'):
                print(resp_json.get('error'))
            else:
                self.token = resp_json.get('token')
        except Exception:
            print("An error occured. Can't login.")

    def start_next_stage(self, candid, visit, site, subproject, project, date):
        resp = requests.patch(
            url=self.url + '/candidates/' + str(candid) + '/' + urllib.parse.quote(visit),
            headers={'Authorization': 'Bearer %s' % self.token, 'LORIS-Overwrite': 'overwrite'},
            data=json.dumps({
                "CandID": candid,
                "Visit": visit,
                "Site": site,
                "Battery": subproject,
                "Project": project,
                "Stages": {
                    "Visit": {
                        "Date": date,
                        "Status": "In Progress",
                    }
                }
            }),
            verify=False
        )

        if (resp.status and resp.status.code and resp.status.code == 200):
            print("Next stage successfully started.")
        else:
            print("An error occured. Can't start next stage.")
