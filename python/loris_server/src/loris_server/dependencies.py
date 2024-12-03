from collections.abc import Iterator
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request
from lib.config import get_jwt_secret_key_config
from lib.db.models.user import DbUser
from lib.db.queries.user import try_get_user_with_username
from lib.env import Env
from lib.make_env import make_env
from lib.user import is_user_account_locked


def get_server_env(request: Request) -> Iterator[Env]:
    """
    Get the LORIS environment.
    """

    config = request.app.state.config
    if config is None:
        raise RuntimeError("Server configuration not initialized.")

    # Create the LORIS environment object for this request.
    env = make_env('server', {}, config, False, log_file=False)

    try:
        # Yield the environment for the request.
        yield env
    finally:
        # Close the environment once the request is handled.
        env.close()


EnvDep = Annotated[Env, Depends(get_server_env)]


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=401,
        detail=detail,
        headers={'WWW-Authenticate': 'Bearer'},
    )


def get_user(env: EnvDep, request: Request) -> DbUser:
    """
    Get the LORIS user that issued the request.
    """

    authorization = request.headers.get('Authorization')
    if authorization is None:
        raise _unauthorized("Authorization header is missing.")

    scheme, separator, token = authorization.partition(' ')
    if separator == '' or scheme.lower() != 'bearer':
        raise _unauthorized("Authorization header must use the Bearer scheme.")

    token = token.strip()
    if token == '':
        raise _unauthorized("Authorization token is missing.")

    secret_key = get_jwt_secret_key_config(env)

    try:
        payload = jwt.decode(  # type: ignore
            token,
            secret_key,
            algorithms=['HS256'],
            # The LORIS PHP JWT implementation does not validate audience, which is therefore also
            # disabled here.
            options={'verify_aud': False},
        )
    except jwt.PyJWTError as exception:
        raise _unauthorized("Login information is incorrect.") from exception

    username = payload.get('user')
    if not isinstance(username, str) or username == '':
        raise _unauthorized("Login information is incorrect.")

    client_ip = request.client.host if request.client is not None else ''
    if is_user_account_locked(env, username, client_ip):
        raise _unauthorized("Login information is incorrect.")

    user = try_get_user_with_username(env.db, username)
    if user is None:
        raise _unauthorized("Login information is incorrect.")

    return user


UserDep = Annotated[DbUser, Depends(get_user)]
