from typing import Any, Literal
from python.lib.dataclass.api import Api


class GetCandidateDicomMeta:
    cand_id: int
    visit:   str

    def __init__(self, object: Any):
        self.cand_id = object['CandID']
        self.visit   = object['Visit']


class GetCandidateDicomTarSeries:
    series_description: str
    series_number:      int
    echo_time:          float
    repetition_time:    int
    inversion_time:     int
    slice_thickness:    int
    modality:           Literal['MR', 'PT']
    series_uid:         str

    def __init__(self, object: Any):
        self.series_description = object['SeriesDescription']
        self.series_number      = object['SeriesNumber']
        self.echo_time          = object['EchoTime']
        self.repetition_time    = object['RepetitionTime']
        self.inversion_time     = object['InversionTime']
        self.slice_thickness    = object['SliceThickness']
        self.modality           = object['Modality']
        self.series_uid         = object['SeriesUID']


class GetCandidateDicomTar:
    tar_name:     str
    patient_name: str
    series:       list[GetCandidateDicomTarSeries]

    def __init__(self, object: Any):
        self.tar_name     = object['Tarname']
        self.patient_name = object['Patientname']
        self.series       = map(GetCandidateDicomTarSeries, object['SeriesInfo'])


class GetCandidateDicom:
    meta: GetCandidateDicomMeta
    tars: list[GetCandidateDicomTar]

    def __init__(self, object: Any):
        self.meta = GetCandidateDicomMeta(object['Meta'])
        self.tars = map(GetCandidateDicomTar, object['DicomTars'])


def get_candidate_dicom(api: Api, cand_id: int, visit: str):
    object = api.call('v0.0.4-dev', f'/candidates/{cand_id}/{visit}/dicoms')
    return GetCandidateDicom(object)
