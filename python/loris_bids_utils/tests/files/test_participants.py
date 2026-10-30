from loris_bids_utils.files.participants import BidsParticipantTsvRow


def test_bids_participant_tsv_row_with_participant_id():
    source_row = BidsParticipantTsvRow({
        'participant_id': 'sub-source01',
        'group': 'Control',
    })

    mapped_row = source_row.with_participant_id('LORIS001')

    assert mapped_row.participant_id == 'LORIS001'
    assert mapped_row.data == {
        'participant_id': 'sub-LORIS001',
        'group': 'Control',
    }
    assert source_row.participant_id == 'source01'
    assert source_row.data == {
        'participant_id': 'sub-source01',
        'group': 'Control',
    }
