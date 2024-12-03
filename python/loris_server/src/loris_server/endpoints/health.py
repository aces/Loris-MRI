from fastapi.responses import PlainTextResponse


def health():
    return PlainTextResponse("It works!")
