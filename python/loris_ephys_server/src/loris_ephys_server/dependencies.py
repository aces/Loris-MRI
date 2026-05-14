
from typing import Annotated

from fastapi import Depends, HTTPException
from lib.db.models.physio_file import DbPhysioFile
from lib.db.queries.physio_file import try_get_physio_file_with_id
from lib.user import can_user_access_session
from loris_server.dependencies import EnvDep, UserDep


def get_physio_file(env: EnvDep, user: UserDep, physio_file_id: int) -> DbPhysioFile:
    """
    Get a physiological file from the query parameters or raise an HTTP 404 error if that file
    does not exist in LORIS or the user does not have the permissions to access it.
    """

    physio_file = try_get_physio_file_with_id(env.db, physio_file_id)
    if physio_file is None:
        raise HTTPException(status_code=404, detail="Electrophysiology file not found or not accessible.")

    if not can_user_access_session(env, user, physio_file.session):
        raise HTTPException(status_code=404, detail="Electrophysiology file not found or not accessible.")

    return physio_file


PhysioFileDep = Annotated[DbPhysioFile, Depends(get_physio_file)]
