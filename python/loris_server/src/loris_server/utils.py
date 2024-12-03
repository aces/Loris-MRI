from collections.abc import Sequence
from mimetypes import guess_type
from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import HTTPException
from fastapi.responses import FileResponse
from loris_utils.archive import create_zip_archive_with_files
from starlette.background import BackgroundTask


def guess_mime_type(path: Path) -> str:
    """
    Guess the MIME type of a file based on its path.
    """

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


class TempZipResponse(FileResponse):
    """
    Build a temporary zip archive for a set of files or directories and return it as a response.
    """

    def __init__(self, paths: Sequence[Path], filename: str):
        with NamedTemporaryFile(prefix='loris_archive_', suffix='.zip', delete=False) as temp_archive:
            archive_path = Path(temp_archive.name)

        try:
            create_zip_archive_with_files(archive_path, paths)
        except Exception as exception:
            archive_path.unlink()
            raise HTTPException(status_code=500, detail="Could not create archive.") from exception

        super().__init__(
            archive_path,
            filename=filename,
            media_type='application/zip',
            background=BackgroundTask(lambda: archive_path.unlink()),
        )
