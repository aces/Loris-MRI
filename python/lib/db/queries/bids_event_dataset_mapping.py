from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.bids_event_dataset_mapping import DbBidsEventDatasetMapping


def get_bids_event_dataset_mappings_with_project_id(
    db: Database,
    project_id: int,
) -> Sequence[DbBidsEventDatasetMapping]:
    """
    Get the BIDS event dataset mappings of project using its ID.
    """

    return db.execute(select(DbBidsEventDatasetMapping)
        .where(DbBidsEventDatasetMapping.project_id == project_id)
    ).scalars().all()
