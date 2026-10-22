from pathlib import Path

import pytest

from loris_bids_utils.files.sessions import BidsSessionsTsvFile


def test_bids_sessions_tsv_file(tmp_path: Path):
    path = tmp_path / 'sub-01_sessions.tsv'
    path.write_text(
        'session_id\tcohort\n'
        'ses-baseline\tControl\n'
        'ses-followup\tPatient\n'
    )

    sessions_file = BidsSessionsTsvFile.read(path)

    baseline = sessions_file.get_row('baseline')
    assert baseline is not None
    assert baseline.session_id == 'baseline'
    assert baseline.data['cohort'] == 'Control'

    followup = sessions_file.get_row('ses-followup')
    assert followup is not None
    assert followup.session_id == 'followup'

    assert sessions_file.get_row('missing') is None


def test_bids_sessions_tsv_file_missing_session_id(tmp_path: Path):
    path = tmp_path / 'sub-01_sessions.tsv'
    path.write_text('cohort\nControl\n')

    with pytest.raises(Exception, match='Missing session_id'):
        BidsSessionsTsvFile.read(path)


def test_bids_session_tsv_row_with_session_id(tmp_path: Path):
    path = tmp_path / 'sub-01_sessions.tsv'
    path.write_text('session_id\ttimepoint\nses-baseline\tfirst\n')
    source_row = BidsSessionsTsvFile.read(path).rows[0]

    mapped_row = source_row.with_session_id('V1')

    assert mapped_row.session_id == 'V1'
    assert mapped_row.data == {'session_id': 'ses-V1', 'timepoint': 'first'}
    assert source_row.session_id == 'baseline'
    assert source_row.data == {'session_id': 'ses-baseline', 'timepoint': 'first'}
