from dataclasses import dataclass

import dateutil.parser
from bids import BIDSLayout

import lib.utilities as utilities
from lib.db.models.candidate import DbCandidate


@dataclass
class BidsParticipant:
    """
    Information about a BIDS participant represented in an entry in the `participants.tsv` file of
    a BIDS dataset.
    """

    id:         str
    birth_date: str | None = None
    sex:        str | None = None
    age:        str | None = None
    site:       str | None = None
    cohort:     str | None = None
    project:    str | None = None
    # FIXME: Both "cohort" and "subproject" are used in scripts, this may be a bug.
    subproject: str | None = None


def read_bids_participants_file(bids_layout: BIDSLayout) -> list[BidsParticipant] | None:
    """
    Find, read and parse the `participants.tsv` file of a BIDS dataset. Return the BIDS participant
    entries if a file is found, or `None` otherwise.
    """

    # Find the `participants.tsv` file in the BIDS dataset.
    bids_participants_file_path = None
    for bids_file_path in bids_layout.get(suffix='participants', return_type='filename'):  # type: ignore
        if 'participants.tsv' in bids_file_path:
            bids_participants_file_path = bids_file_path  # type: ignore
            break

    # If no `participants.tsv` file is found, return `None`.
    if bids_participants_file_path is None:
        return None

    # Parse the BIDS participant entries from the `participants.tsv` file.
    bids_participant_rows = utilities.read_tsv_file(bids_participants_file_path)  # type: ignore
    return list(map(read_bids_participant_row, bids_participant_rows))  # type: ignore


def read_bids_participant_row(row: dict[str, str]) -> BidsParticipant:
    """
    Get a BIDS participant entry from a parsed TSV line of a `participants.tsv` file.
    """

    # Get the participant ID by removing the `sub-` prefix if it is present.
    participant_id = row['participant_id'].replace('sub-', '')

    # Get the participant date of birth from one of the possible date of birth fields.
    birth_date = None
    for birth_date_name in ['date_of_birth', 'birth_date', 'dob']:
        if birth_date_name in row:
            birth_date = dateutil.parser.parse(row[birth_date_name]).strftime('%Y-%m-%d')
            break

    # Create the BIDS participant object.
    return BidsParticipant(
        id         = participant_id,
        birth_date = birth_date,
        sex        = row.get('sex'),
        age        = row.get('age'),
        site       = row.get('site'),
        cohort     = row.get('cohort'),
        project    = row.get('project'),
        subproject = row.get('subproject'),
    )


def get_bids_participant_from_candidate(candidate: DbCandidate) -> BidsParticipant:
    """
    Generate a BIDS participant entry from a database candidate.
    """

    # Stringify the candidate date of birth if there is one.
    birth_date = candidate.date_of_birth.strftime('%Y-%m-%d') if candidate.date_of_birth is not None else None

    # Create the BIDS participant object corresponding to the database candidate.
    return BidsParticipant(
        id         = candidate.psc_id,
        birth_date = birth_date,
        sex        = candidate.sex,
        site       = candidate.registration_site.name,
        project    = candidate.registration_project.name,
    )
