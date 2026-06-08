from fastapi import APIRouter, FastAPI
from fastapi.responses import FileResponse, StreamingResponse
from loris_server.dependencies import EnvDep

from loris_meegqc_module.dependencies import PhysioFileDep
from loris_meegqc_module.endpoints.meegqc_files import (
    MeegqcFilesResponse,
    download_meegqc_files_archive,
    get_meegqc_file,
    list_meegqc_files,
)

router = APIRouter(prefix='/ephys')


@router.get('/{physio_file_id}/meegqc/files', response_model=MeegqcFilesResponse)
def meegqc_files(env: EnvDep, physio_file: PhysioFileDep):
    return list_meegqc_files(env, physio_file)


@router.get('/{physio_file_id}/meegqc/files/download', response_class=StreamingResponse)
def meegqc_files_download(env: EnvDep, physio_file: PhysioFileDep, category: str | None = None):
    return download_meegqc_files_archive(env, physio_file, category)


@router.get('/{physio_file_id}/meegqc/files/{meegqc_file_id}', response_class=FileResponse)
def meegqc_file(env: EnvDep, physio_file: PhysioFileDep, meegqc_file_id: int):
    return get_meegqc_file(env, physio_file, meegqc_file_id)


def load(api: FastAPI):
    return api.include_router(router)
