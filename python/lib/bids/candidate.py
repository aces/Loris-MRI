import sys
from typing import Optional

from bids.layout import BIDSLayout
from sqlalchemy.orm import Session as Database

from lib.db.models.candidate import DbCandidate
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.util import filter_map, try_parse_int


def get_bids_candidates(db: Database, bids_layout: BIDSLayout) -> list[DbCandidate]:
    """
    Get all the candidates of a BIDS dataset from the database, using the BIDS subject labels.
    """

    # Get the subject labels of the BIDS dataset.
    bids_subject_labels: list[str] = bids_layout.get_subjects()  # type: ignore

    # Return the candidates found for each subject label.
    return list(filter_map(
        lambda bids_subject_label: get_bids_candidate(db, bids_subject_label),
        bids_subject_labels,
    ))


def get_bids_candidate(db: Database, bids_subject_label: str) -> Optional[DbCandidate]:
    """
    Get a candidate from the database using a BIDS subject label.
    """

    # Check if the BIDS subject label looks might be a CandID.
    cand_id = try_parse_int(bids_subject_label)

    # If the BIDS subject label might be a CandID, try to get the candidate using it as a CandID.
    if cand_id is not None:
        candidate = try_get_candidate_with_cand_id(db, cand_id)
        if candidate is not None:
            return candidate

    # Try to get the candidate using the BIDS subject label as a PSCID.
    candidate = try_get_candidate_with_psc_id(db, bids_subject_label)
    if candidate is not None:
        return candidate

    # All the candidates of the BIDS dataset should have been in the database at this stage. Print
    # a warning if no candidate was found.
    print(
        (
            f"WARNING: No candidate found for BIDS subject label '{bids_subject_label}',"
            " candidate omitted from the participants file"
        ),
        file=sys.stderr,
    )

    # Return `None` if no candidate is found.
    return None
