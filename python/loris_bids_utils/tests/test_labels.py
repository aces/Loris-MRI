from loris_bids_utils.labels import BidsSessionLabel, BidsSubjectLabel, BidsSubjectSessionLabel


def test_bids_subject_session_label_display_name():
    subject = BidsSubjectLabel('01')
    session = BidsSessionLabel('baseline')

    assert BidsSubjectSessionLabel(subject, session).display_name == 'sub-01/ses-baseline'
    assert BidsSubjectSessionLabel(subject, None).display_name == 'sub-01'
