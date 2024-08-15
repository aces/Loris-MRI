from datetime import datetime
from typing import Any, Literal
from python.lib.dataclass.api import Api


class GetCandidateDicomProcessesProcess:
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


class GetCandidateDicomProcessesUpload:
    upload_id: int
    processes: list[GetCandidateDicomProcessesProcess]

    def __init__(self, object: Any):
        self.upload_id = object['mri_upload_id']
        self.processes = map(GetCandidateDicomProcessesProcess, object['processes'])


class GetCandidateDicomProcesses:
    mri_uploads: list[GetCandidateDicomProcessesUpload]

    def __init__(self, object: Any):
        self.mri_uploads = map(GetCandidateDicomProcessesUpload, object['mri_uploads'])


def get_candidate_dicom_processes(api: Api, cand_id: int, visit_label: str, dicom_tar_name: str):
    object = api.get('v0.0.4-dev', f'/candidates/{cand_id}/{visit_label}/dicoms/{dicom_tar_name}/processes')
    return GetCandidateDicomProcesses(object)
