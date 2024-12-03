from pathlib import Path

from fastapi import HTTPException
from fastapi.responses import FileResponse
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from loris_server.utils import TempZipResponse, guess_mime_type
from pydantic import BaseModel

from loris_meegqc_module.database.queries.meegqc_file import (
    get_meegqc_files_with_acquisition_file_id,
    get_meegqc_files_with_acquisition_file_id_category,
    try_get_meegqc_file_with_id_acquisition_file_id,
)


class MeegqcFileResponse(BaseModel):
    id: int
    name: str
    category: str
    blake2b_hash: str


class MeegqcFilesResponse(BaseModel):
    files: list[MeegqcFileResponse]


def list_meegqc_files(env: Env, acquisition_file: DbPhysioFile) -> MeegqcFilesResponse:
    """
    List the MEEGqc files associated with a given acquisition file.
    """

    meegqc_files = get_meegqc_files_with_acquisition_file_id(env.db, acquisition_file.id)

    return MeegqcFilesResponse(
        files=[
            MeegqcFileResponse(
                id           = meegqc_file.id,
                name         = meegqc_file.bids_info.path.name,
                category     = meegqc_file.category,
                blake2b_hash = meegqc_file.bids_info.blake2b_hash,
            )
            for meegqc_file in meegqc_files
        ],
    )


def get_meegqc_file(env: Env, acquisition_file: DbPhysioFile, meegqc_file_id: int) -> FileResponse:
    """
    Get an MEEGqc file.
    """

    meegqc_file = try_get_meegqc_file_with_id_acquisition_file_id(env.db, meegqc_file_id, acquisition_file.id)
    if meegqc_file is None:
        raise HTTPException(status_code=404, detail="MEEGqc file not found or not accessible.")

    data_dir_path = get_data_dir_path_config(env)

    meegqc_file_path = data_dir_path / meegqc_file.bids_info.dataset.path / meegqc_file.bids_info.path

    media_type = guess_mime_type(meegqc_file.bids_info.path)

    return FileResponse(
        meegqc_file_path,
        filename                 = meegqc_file.bids_info.path.name,
        media_type               = media_type,
        content_disposition_type = 'inline',
    )


def get_meegqc_files_archive(
    env: Env,
    acquisition_file: DbPhysioFile,
    category: str | None,
) -> FileResponse:
    """
    Get the MEEGqc files associated with an acquisition file as a downloadable archive.
    """

    if category is None:
        meegqc_files = get_meegqc_files_with_acquisition_file_id(env.db, acquisition_file.id)
    else:
        meegqc_files = get_meegqc_files_with_acquisition_file_id_category(env.db, acquisition_file.id, category)

    if meegqc_files == []:
        raise HTTPException(status_code=404, detail="MEEGqc files not found.")

    data_dir_path = get_data_dir_path_config(env)

    meegqc_file_paths = [
        data_dir_path / meegqc_file.bids_info.dataset.path / meegqc_file.bids_info.path
        for meegqc_file in meegqc_files
    ]

    meegqc_archive_name = get_meegqc_archive_name(acquisition_file.path, category)

    return TempZipResponse(meegqc_file_paths, meegqc_archive_name)


def get_meegqc_archive_name(acquisition_file_path: Path, category: str | None) -> str:
    """
    Get the name of a new MEEGqc file archive.
    """

    archive_name = f'{acquisition_file_path.stem}_meegqc'

    if category is not None:
        archive_name += f'_{category}'

    return f'{archive_name}.zip'
