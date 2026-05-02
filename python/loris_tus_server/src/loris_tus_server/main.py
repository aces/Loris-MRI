import os
from pathlib import Path

from fastapi import APIRouter, FastAPI
from tuspyserver import create_tus_router  # type: ignore


def get_upload_dir() -> Path:
    """Get the upload directory from environment or use default"""
    upload_dir = os.environ.get('TUS_UPLOAD_DIR', '/data/bic/tmp/tus')
    return Path(upload_dir)


def load(api: FastAPI):
    """Load the TUS server endpoints into the main LORIS server"""
    upload_dir = get_upload_dir()
    upload_dir.mkdir(parents=True, exist_ok=True)

    # Initialize TUS router with the upload directory
    # tus_router = TusRouter(upload_dir=str(upload_dir))

    router: APIRouter = create_tus_router(  # type: ignore
        prefix='/ephys/upload',
        files_dir=str(upload_dir),
    )

    # Include TUS routes in the FastAPI app
    api.include_router(router)  # type: ignore
