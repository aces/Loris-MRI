from pathlib import Path


def get_path_stem(path: Path) -> str:
    """
    Get the stem of a path, that is, the name of the file without its extension (including multiple
    extensions).
    """

    parts = path.name.split('.')
    return parts[0]


def get_path_extension(path: Path) -> str | None:
    """
    Get the extension (including multiple extensions) of a path without the leading dot.
    """

    # Remove the leading dot if there is none.
    stripped_name = path.name.lstrip('.')

    parts = stripped_name.split('.', maxsplit=1)
    if len(parts) == 1:
        return None

    return parts[1]


def add_path_extension(path: Path, extension: str) -> Path:
    """
    Add an extension to a path, in addition to the existing extension if there is one.
    """

    return path.with_name(f'{path.name}.{extension}')


def remove_path_extension(path: Path) -> Path:
    """
    Remove the extension (including multiple extensions) of a path.
    """

    return path.with_name(remove_name_extension(path.name))


def replace_path_extension(path: Path, extension: str) -> Path:
    """
    Replace the extension (including multiple extensions) of a path by another extension.
    """

    parts = path.name.split('.')
    return path.with_name(f'{parts[0]}.{extension}')


def remove_name_extension(name: str) -> str:
    """
    Remove the extension (including multiple extensions) of a file name.
    """

    return name.split('.')[0]
