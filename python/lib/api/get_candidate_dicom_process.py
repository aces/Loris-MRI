from datetime import datetime
from typing import Any, Literal
from lib.api import Api


class GetCandidateDicomProcess:
    end_time:  datetime
    exit_code: int
    id:        int
    pid:       int
    progress:  str
    state:     Literal['SUCCESS', 'RUNNING', 'ERROR']

    def __init__(self, object: Any):
        self.end_time  = object['END_TIME']
        self.exit_code = object['EXIT_CODE']
        self.id        = object['ID']
        self.pid       = object['PID']
        self.progress  = object['PROGRESS']
        self.state     = object['STATE']


def get_candidate_dicom_process(api: Api, cand_id: int, visit_label: str, dicom_tar_name: str, process_id: int):
    object = api.call(
        'v0.0.4-dev',
        f'/candidates/{cand_id}/{visit_label}/dicoms/{dicom_tar_name}/processes/{process_id}'
    )

    return GetCandidateDicomProcess(object)
