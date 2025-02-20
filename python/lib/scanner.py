import random
from datetime import datetime

from sqlalchemy.orm import Session as Database

from lib.db.models.candidate import DbCandidate
from lib.db.models.mri_scanner import DbMriScanner
from lib.db.queries.candidate import try_get_candidate_with_cand_id
from lib.db.queries.mri_scanner import try_get_scanner_with_info
from lib.env import Env


def get_or_create_scanner(
    env: Env,
    manufacturer: str,
    model: str,
    serial_number: str,
    software_version: str,
    site_id: int,
    project_id: int,
) -> DbMriScanner:
    """
    Get an MRI scanner from the database using the provided information, or create it if it does
    not already exist.
    """

    mri_scanner = try_get_scanner_with_info(env.db, manufacturer, model, serial_number, software_version)

    if mri_scanner is not None:
        return mri_scanner

    cand_id = generate_new_cand_id(env.db)
    now = datetime.now()

    candidate = DbCandidate(
        cand_id                 = cand_id,
        psc_id                  = 'scanner',
        registration_site_id    = site_id,
        registration_project_id = project_id,
        user_id                 = 'imaging.py',
        entity_type             = 'Scanner',
        date_active             = now,
        date_registered         = now,
        active                  = True,
    )

    env.db.add(candidate)
    env.db.commit()

    mri_scanner = DbMriScanner(
        manufacturer     = manufacturer,
        model            = model,
        serial_number    = serial_number,
        software_version = software_version,
        candidate_id     = candidate.id,
    )

    env.db.add(mri_scanner)
    env.db.commit()

    return mri_scanner


# TODO: Move this function to a more appropriate place.
def generate_new_cand_id(db: Database) -> int:
    """
    Generate a new random CandID that is not already in the database.
    """

    while True:
        cand_id = random.randint(100000, 999999)
        candidate = try_get_candidate_with_cand_id(db, cand_id)
        if candidate is None:
            return cand_id
