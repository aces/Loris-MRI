from dataclasses import dataclass

from loris_bids_reader.files.participants import BidsParticipantTsvRow


@dataclass
class BidsSubjectInfo:
    """
    Information about a BIDS subject directory.
    """

    subject: str
    """
    The BIDS subject label.
    """

    participant_row: BidsParticipantTsvRow | None
    """
    The BIDS `participants.tsv` row of this subject, if any.
    """


@dataclass
class BidsSessionInfo(BidsSubjectInfo):
    """
    Information about a BIDS session directory.
    """

    session: str | None
    """
    The BIDS session label.
    """


@dataclass
class BidsDataTypeInfo(BidsSessionInfo):
    """
    Information about a BIDS data type directory.
    """

    data_type: str
    """
    The BIDS data type name.
    """
