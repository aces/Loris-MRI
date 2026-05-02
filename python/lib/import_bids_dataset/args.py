from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass
class Args:
    source_bids_path: Path
    type: Literal[None, 'raw', 'derivative']
    bids_validation: bool
    create_candidate: bool
    create_session: bool
    copy: bool
    verbose: bool
