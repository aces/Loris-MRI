import os
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request
from lib.config import get_jwt_secret_key_config
from lib.db.models.user import DbUser
from lib.db.queries.user import try_get_user_with_id
from lib.env import Env
from lib.make_env import make_env


def get_server_env(request: Request) -> Env:
    """
    Get the LORIS environment.
    """

    config = request.app.state.config
    if config is None:
        raise RuntimeError("Server configuration not initialized.")

    # Create the LORIS environment object for this request.
    return make_env('server', {}, config, os.environ['TMPDIR'], False)


EnvDep = Annotated[Env, Depends(get_server_env)]


def get_user(env: EnvDep, request: Request) -> DbUser:
    """
    Get the LORIS user that issued the request.
    """

    bearer = request.headers.get('Authorization')
    if bearer is None:
        raise HTTPException(status_code=401, detail="Authorization header is missing.")

    token = bearer.removeprefix('Bearer ').strip()
    if token == '':
        raise HTTPException(status_code=401, detail="Authorization token is missing.")

    secret_key = get_jwt_secret_key_config(env)

    payload = jwt.decode(token, secret_key, algorithms=['HS256'])  # type: ignore
    user_info = payload.get('user')
    if user_info is None:
        raise HTTPException(status_code=401, detail="Login information is incorrect.")

    user_id = user_info.get('userID')
    if user_id is None:
        raise HTTPException(status_code=401, detail="Login information is incorrect.")

    user = try_get_user_with_id(env.db, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Login information is incorrect.")

    return user


UserDep = Annotated[DbUser, Depends(get_user)]
