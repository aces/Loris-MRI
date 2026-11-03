from pathlib import Path

import pytest

from loris_bids_utils.files.events import BidsEventTsvRow
from loris_bids_utils.files.participants import BidsParticipantTsvRow
from loris_bids_utils.files.scans import BidsScanTsvRow
from loris_bids_utils.tsv import BidsTsvFile, BidsTsvRow


class MissingValueRow(BidsTsvRow):
    def __init__(self, data: dict[str, str | None]):
        # Subclasses receive normalized values even before calling the base constructor.
        assert data['value'] is None
        super().__init__(data)


@pytest.mark.parametrize('value', [None, '', 'n/a', 'N/A', 'N/a', 'n/A'])
def test_missing_values_are_normalized_before_constructing_rows(value: str | None, tmp_path: Path):
    path = tmp_path / 'values.tsv'
    # A short row exercises DictReader's None for an absent cell.
    row = 'text' if value is None else f'text\t{value}'
    path.write_text(f'other\tvalue\n{row}\n', encoding='utf-8-sig')
    assert BidsTsvFile(MissingValueRow, path).rows[0].data == {'other': 'text', 'value': None}


@pytest.mark.parametrize('value', ['na', 'NA', 'NaN', ' n/a ', ' name ', '0'])
def test_non_missing_strings_are_preserved(value: str, tmp_path: Path):
    path = tmp_path / 'values.tsv'
    path.write_text(f'value\n{value}\n')
    assert BidsTsvFile(BidsTsvRow, path).rows[0].data['value'] == value


def test_events_use_normalized_values(tmp_path: Path):
    path = tmp_path / 'events.tsv'
    path.write_text(
        'onset\tduration\tevent_code\tevent_sample\tevent_value\ttrial_type\n'
        '0\tN/A\tn/a\tN/A\tn/a\tNA\n'
    )
    row = BidsTsvFile(BidsEventTsvRow, path).rows[0]
    assert row.onset == 0
    assert row.duration is None
    assert row.event_code is None
    assert row.event_sample is None
    assert row.event_value is None
    assert row.trial_type == 'NA'


def test_scans_and_participants_use_normalized_values(tmp_path: Path):
    scans_path = tmp_path / 'scans.tsv'
    scans_path.write_text('filename\tacq_time\tage\neeg/file.edf\tN/A\tn/a\n')
    scan = BidsTsvFile(BidsScanTsvRow, scans_path).rows[0]
    assert scan.get_acquisition_time() is None
    assert scan.get_age_at_scan() is None
    participants_path = tmp_path / 'participants.tsv'
    participants_path.write_text('participant_id\tsex\tsite\nsub-01\tN/A\tNA\n')
    participant = BidsTsvFile(BidsParticipantTsvRow, participants_path).rows[0]
    assert participant.sex is None
    assert participant.site == 'NA'
