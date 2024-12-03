from fastapi import APIRouter, FastAPI
from loris_server.dependencies import EnvDep

from loris_ephys_server.dependencies import PhysioFileDep
from loris_ephys_server.endpoints.meg_head_shape import MegHeadShapeResponse, get_meg_head_shape
from loris_ephys_server.endpoints.meg_sensors import MegSensorsResponse, get_meg_sensors
from loris_ephys_server.endpoints.topographic_map import get_topographic_map

router = APIRouter(prefix='/ephys')


@router.get('/{physio_file_id}/topographic-map')
def topographic_map(
    env: EnvDep,
    physio_file: PhysioFileDep,
    tmin: float | None = None,
    tmax: float | None = None,
    lfreq: float | None = None,
    hfreq: float | None = None,
):
    return get_topographic_map(env, physio_file, tmin, tmax, lfreq, hfreq)


@router.get('/{physio_file_id}/meg/sensors', response_model=MegSensorsResponse)
def meg_sensors(env: EnvDep, physio_file: PhysioFileDep):
    return get_meg_sensors(env, physio_file)


@router.get('/{physio_file_id}/meg/headshape', response_model=MegHeadShapeResponse)
def meg_head_shape(env: EnvDep, physio_file: PhysioFileDep):
    return get_meg_head_shape(env, physio_file)


def load(api: FastAPI):
    return api.include_router(router)
