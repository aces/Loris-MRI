from pathlib import Path

import pytest

from loris_utils.path import get_path_extension


@pytest.mark.parametrize(('name', 'extension'), [
    ('README', None),
    ('.bidsignore', None),
    ('.gitignore', None),
    ('.config.json', 'json'),
    ('.backup.tar.gz', 'tar.gz'),
    ('..config.json', 'json'),
    ('scan.nii.gz', 'nii.gz'),
    ('events.tsv.gz', 'tsv.gz'),
    ('dataset_description.json', 'json'),
    ('directory.with.dots/README', None),
    ('directory.with.dots/.bidsignore', None),
    ('directory.with.dots/.config.json', 'json'),
])
def test_get_path_extension(name: str, extension: str | None):
    assert get_path_extension(Path(name)) == extension
