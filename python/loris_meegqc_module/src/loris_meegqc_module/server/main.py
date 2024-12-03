from fastapi import APIRouter, FastAPI
from fastapi.responses import FileResponse
from loris_server.dependencies import EnvDep

from loris_meegqc_module.server.dependencies import PhysioFileDep
from loris_meegqc_module.server.endpoints import (
    MeegqcFilesResponse,
    get_meegqc_file,
    get_meegqc_files_archive,
    list_meegqc_files,
)

router = APIRouter(prefix='/meegqc')


@router.get('/{physio_file_id}/files', response_model=MeegqcFilesResponse)
def meegqc_files(env: EnvDep, physio_file: PhysioFileDep):
    return list_meegqc_files(env, physio_file)


@router.get('/{physio_file_id}/files/archive', response_class=FileResponse)
def meegqc_files_archive(env: EnvDep, physio_file: PhysioFileDep, category: str | None = None):
    return get_meegqc_files_archive(env, physio_file, category)


@router.get('/{physio_file_id}/files/{meegqc_file_id}', response_class=FileResponse)
def meegqc_file(env: EnvDep, physio_file: PhysioFileDep, meegqc_file_id: int):
    return get_meegqc_file(env, physio_file, meegqc_file_id)


def load(api: FastAPI):
    return api.include_router(router)
