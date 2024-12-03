from loris_server.main import EnvDep, api

from loris_meg.endpoints.channels import get_meg_channels
from loris_meg.endpoints.head_shape import get_meg_head_shape
from loris_meg.jsonize import jsonize


def module():
    pass


@api.get('/meg/{physio_file_id}/channels')
def meg_channels(physio_file_id: int, env: EnvDep):
    return {'channels': get_meg_channels(env, physio_file_id)}


@api.get('/meg/{physio_file_id}/headshape')
def meg_head_shape(physio_file_id: int, env: EnvDep):
    return jsonize(get_meg_head_shape(env, physio_file_id))
