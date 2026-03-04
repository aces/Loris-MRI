from dataclasses import dataclass

from loris_bids_reader.files.participants import BidsParticipantTsvRow
from loris_bids_reader.files.scans import BidsScansTsvFile, BidsScanTsvRow


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

    scans_file: BidsScansTsvFile | None
    """
    The BIDS `scans.tsv` file of this session, if any.
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


@dataclass
class BidsAcquisitionInfo(BidsDataTypeInfo):
    """
    Information about a BIDS acquisition.
    """

    name: str
    """
    The name of this acquisition (usually the file name without the extension).
    """

    suffix: str | None
    """
    The BIDS suffix of this acquisition, if any.
    """

    scan_row: BidsScanTsvRow | None
    """
    The BIDS `scans.tsv` row of this acquisition, if any.
    """
