import json
import os
from typing import Any

import lib.utilities
from lib.database import Database
from lib.env import Env
from lib.imaging_lib.bids.dataset import BidsDataset
from lib.import_bids_dataset.args import Args
from lib.logging import log_warning
from lib.physiological import Physiological
from lib.util.crypto import compute_file_blake2b_hash


def get_events_metadata(
    env: Env,
    args: Args,
    bids: BidsDataset,
    legacy_db: Database,
    loris_bids_path: str,
    project_id: int,
) -> dict[Any, Any]:
    """
    Get the root level 'events.json' data, assuming a singe project for the BIDS dataset.
    """

    root_event_metadata_file = bids.layout.get_nearest(  # type: ignore
        bids.path,
        return_type='tuple',
        strict=False,
        extension='json',
        suffix='events',
        all_=False,
        subject=None,
        session=None,
    )

    if not root_event_metadata_file:
        log_warning(env, "No event metadata files (events.json) in the BIDS root directory.")
        return {}

    # Copy the event file to the LORIS BIDS import directory.

    copy_file = str.replace(root_event_metadata_file.path, bids.layout.root, '')  # type: ignore

    if args.copy:
        event_metadata_path = os.path.join(loris_bids_path, copy_file)
        lib.utilities.copy_file(root_event_metadata_file.path, event_metadata_path, args.verbose)  # type: ignore

    hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
    hed_union = legacy_db.pselect(query=hed_query, args=())  # type: ignore

    # load json data
    with open(root_event_metadata_file.path) as metadata_file:  # type: ignore
        event_metadata = json.load(metadata_file)

    blake2 = compute_file_blake2b_hash(root_event_metadata_file.path)  # type: ignore
    physio = Physiological(legacy_db, args.verbose)
    _, dataset_tag_dict = physio.insert_event_metadata(  # type: ignore
        event_metadata=event_metadata,
        event_metadata_file=event_metadata_path,  # type: ignore
        physiological_file_id=None,
        project_id=project_id,
        blake2=blake2,
        project_wide=True,
        hed_union=hed_union  # type: ignore
    )

    return dataset_tag_dict  # type: ignore
