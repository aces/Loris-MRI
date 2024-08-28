from dataclasses import dataclass
from typing import Any, Literal
from lib.dataclass.api import Api


@dataclass
class GetCandidateDicomMeta:
    cand_id: int
    visit:   str

    def __init__(self, object: Any):
        self.cand_id = object['CandID']
        self.visit   = object['Visit']


@dataclass
class GetCandidateDicomTarSeries:
    series_description: str
    series_number:      int
    echo_time:          float | None
    repetition_time:    int | None
    inversion_time:     int | None
    slice_thickness:    int | None
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


@dataclass
class GetCandidateDicomTar:
    tar_name:     str
    patient_name: str
    series:       list[GetCandidateDicomTarSeries]

    def __init__(self, object: Any):
        self.tar_name     = object['ArchiveName']
        self.patient_name = object['PatientName']
        self.series       = list(map(GetCandidateDicomTarSeries, object['SeriesInfo']))


@dataclass
class GetCandidateDicom:
    meta: GetCandidateDicomMeta
    tars: list[GetCandidateDicomTar]

    def __init__(self, object: Any):
        self.meta = GetCandidateDicomMeta(object['Meta'])
        self.tars = list(map(GetCandidateDicomTar, object['DicomArchives']))


def get_candidate_dicom(api: Api, cand_id: int, visit: str):
    response = api.get('v0.0.4-dev', f'/candidates/{cand_id}/{visit}/dicoms')
    return GetCandidateDicom(response.json())
