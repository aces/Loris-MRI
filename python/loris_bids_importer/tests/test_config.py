from pathlib import Path

import pytest

from loris_bids_importer.config import (
    BidsCandidateConfig,
    BidsConfigError,
    BidsSessionConfig,
    load_bids_config,
)


def test_load_default_bids_config():
    config = load_bids_config(None)

    assert config.get_candidate(None, '123456', None) == BidsCandidateConfig(cand_id=123456)  # type: ignore[arg-type]
    assert config.get_candidate(None, 'ABC001', None) == BidsCandidateConfig(psc_id='ABC001')  # type: ignore[arg-type]

    with pytest.raises(BidsConfigError, match='without session labels'):
        config.get_session(None, BidsCandidateConfig(psc_id='ABC001'), 'ABC001', None, None, None)  # type: ignore[arg-type]


def test_load_custom_bids_config(tmp_path: Path):
    path = tmp_path / 'bids_config.py'
    path.write_text(
        'from loris_bids_importer.config import BidsCandidateConfig, BidsSessionConfig\n'
        '\n'
        'def get_bids_candidate_config(env, subject_label, participant_row):\n'
        '    return BidsCandidateConfig(psc_id=f"LORIS-{subject_label}")\n'
        '\n'
        'def get_bids_session_config(\n'
        '    env, candidate_config, subject_label, session_label, participant_row, session_row\n'
        '):\n'
        '    return BidsSessionConfig(visit_label=f"VISIT-{session_label}")\n'
    )

    config = load_bids_config(path)

    assert config.get_candidate(None, '01', None) == BidsCandidateConfig(psc_id='LORIS-01')  # type: ignore[arg-type]
    assert config.get_session(None, BidsCandidateConfig(psc_id='ABC001'), '01', '01', None, None) == BidsSessionConfig(  # type: ignore[arg-type]
        visit_label='VISIT-01'
    )


def test_load_custom_bids_config_missing_function(tmp_path: Path):
    path = tmp_path / 'bids_config.py'
    path.write_text('def get_bids_candidate_config(env, subject_label, participant_row):\n    return None\n')

    with pytest.raises(BidsConfigError, match='get_bids_session_config'):
        load_bids_config(path)
