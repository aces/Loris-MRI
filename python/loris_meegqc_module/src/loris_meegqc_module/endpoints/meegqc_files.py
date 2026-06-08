from io import BytesIO
from mimetypes import guess_type
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from fastapi import HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from pydantic import BaseModel

from loris_meegqc_module.database.queries.meegqc_file import (
    get_meegqc_files_with_acquisition_file_id,
    get_meegqc_files_with_acquisition_file_id_kind,
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
    meegqc_files = get_meegqc_files_with_acquisition_file_id(env.db, acquisition_file.id)

    return MeegqcFilesResponse(
        files=[
            MeegqcFileResponse(
                id           = meegqc_file.id,
                name         = meegqc_file.path.name,
                category     = meegqc_file.category,
                blake2b_hash = meegqc_file.blake2b_hash,
            )
            for meegqc_file in meegqc_files
        ],
    )


def get_meegqc_file(env: Env, acquisition_file: DbPhysioFile, meegqc_file_id: int) -> FileResponse:
    meegqc_file = try_get_meegqc_file_with_id_acquisition_file_id(env.db, meegqc_file_id, acquisition_file.id)
    if meegqc_file is None:
        raise HTTPException(status_code=404, detail="MEEGqc file not found or not accessible.")

    data_dir_path = get_data_dir_path_config(env)
    file_path = data_dir_path / meegqc_file.path

    if not file_path.is_file():
        raise HTTPException(status_code=500, detail="MEEGqc file not found.")

    media_type = _guess_display_media_type(meegqc_file.path)

    return FileResponse(
        file_path,
        filename                 = meegqc_file.path.name,
        media_type               = media_type or 'application/octet-stream',
        content_disposition_type = 'inline',
    )


def download_meegqc_files_archive(
    env: Env,
    acquisition_file: DbPhysioFile,
    category: str | None,
) -> StreamingResponse:
    if category is None:
        meegqc_files = get_meegqc_files_with_acquisition_file_id(env.db, acquisition_file.id)
    else:
        meegqc_files = get_meegqc_files_with_acquisition_file_id_kind(env.db, acquisition_file.id, category)

    if len(meegqc_files) == 0:
        if category is None:
            raise HTTPException(status_code=404, detail="No MEEGqc files found or accessible.")

        raise HTTPException(status_code=404, detail="No MEEGqc files of the requested category found or accessible.")

    data_dir_path = get_data_dir_path_config(env)

    # TODO: Factorize this is in loris-utils.
    buffer = BytesIO()
    with ZipFile(buffer, 'w', ZIP_DEFLATED) as archive:
        for meegqc_file in meegqc_files:
            file_path = data_dir_path / meegqc_file.path
            if not file_path.is_file():
                raise HTTPException(status_code=500, detail="MEEGqc file not found.")

            archive.write(file_path, meegqc_file.path.name)

    buffer.seek(0)

    archive_name = _make_meegqc_archive_name(acquisition_file.path, category)
    return StreamingResponse(
        buffer,
        media_type='application/zip',
        headers={'Content-Disposition': f'attachment; filename="{archive_name}"'},
    )


def _guess_display_media_type(path: Path) -> str:
    # Describe TSV files as plain text so that the client can directly visualize them in their web
    # browser.
    if path.suffix == '.tsv':
        return 'text/plain'

    media_type, _ = guess_type(path.name)
    if media_type is not None:
        return media_type

    # Return unknown files as binary files for the client to download, who can then use the
    # appropriate application to visualize them.
    return 'application/octet-stream'


def _make_meegqc_archive_name(acquisition_file_path: Path, category: str | None) -> str:
    archive_name = f'{acquisition_file_path.stem}_meegqc'

    if category is not None:
        archive_name += f'_{category}'

    return f'{archive_name}.zip'
