from decimal import Decimal
from pathlib import Path

import pytest

from loris_bids_utils.eeg.channels import BidsEegChannelsTsvFile, BidsEegChannelTsvRow


def test_parse_channels_with_missing_values(tmp_path: Path):
    path = tmp_path / 'channels.tsv'
    path.write_text(
        'name\ttype\tunits\tstatus\tdescription\tnotch\n'
        'E1\tn/a\tN/A\tn/a\tNA\tN/A\n'
        'E2\tEEG\tuV\tgood\tn/a\t50\n'
    )
    missing, known = BidsEegChannelsTsvFile(path).rows
    assert missing.name == 'E1'
    assert missing.type is None
    assert missing.unit is None
    assert missing.status is None
    assert missing.description == 'NA'
    assert missing.notch is None
    assert known.type == 'EEG'
    assert known.unit == 'uV'
    assert known.description is None
    assert known.notch == Decimal(50)


@pytest.mark.parametrize('column', ['type', 'units'])
def test_required_columns_cannot_be_absent(column: str):
    data: dict[str, str | None] = {'name': 'E1', 'type': None, 'units': 'uV'}
    del data[column]
    with pytest.raises(Exception, match=r'Missing channel .* column'):
        BidsEegChannelTsvRow(data)


@pytest.mark.parametrize('name', [None, '', 'n/a', 'N/A'])
def test_channel_name_cannot_be_missing(name: str | None, tmp_path: Path):
    path = tmp_path / 'channels.tsv'
    path.write_text(f'name\ttype\tunits\n{name or ""}\tEEG\tuV\n')
    with pytest.raises(Exception, match='Missing channel name'):
        BidsEegChannelsTsvFile(path)
