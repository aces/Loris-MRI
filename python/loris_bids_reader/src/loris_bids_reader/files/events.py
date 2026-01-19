from pathlib import Path
from typing import Any

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsEventTsvRow(BidsTsvRow):
    """
    Class representing a BIDS events.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html
    """

    onset: float
    duration: float
    response_time: float | None
    event_sample: float | None
    event_value: str | None
    trial_type: str | None

    def __init__(self, data: dict[str, Any]):
        super().__init__(data)

        # nullify not present optional cols
        for field in OPTIONAL_EVENT_FIELDS:
            if field not in data.keys():
                data[field] = None

        if isinstance(data['onset'], int | float):
            self.onset = data['onset']
        else:
            # try casting to float, cannot be n/a
            # should raise an error if not a number
            self.onset = float(data['onset'])

        if isinstance(data['duration'], int | float):
            self.duration = data['duration']
        else:
            try:
                # try casting to float
                self.duration = float(data['duration'])
            except ValueError:
                # value could be 'n/a',
                # should not raise
                # let default value (0)
                self.duration = 0

        assert self.duration >= 0

        if isinstance(data['response_time'], int | float):
            self.response_time = data['response_time']
        else:
            self.response_time = None

        if isinstance(data['event_sample'], int | float):
            self.event_sample = data['event_sample']
        elif isinstance(data['sample'], int | float):
            self.event_sample = data['sample']
        else:
            self.event_sample = None

        if data['event_value']:
            self.event_value = str(data['event_value'])
        elif data['value']:
            self.event_value = str(data['value'])
        else:
            self.event_value = None

        if data['trial_type']:
            self.trial_type = str(data['trial_type'])
        else:
            self.trial_type = None


class BidsEventsTsvFile(BidsTsvFile[BidsEventTsvRow]):
    """
    Class representing a BIDS events.tsv file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html
    """

    def __init__(self, path: Path):
        super().__init__(BidsEventTsvRow, path)


# known opt fields
OPTIONAL_EVENT_FIELDS = [
    'trial_type', 'response_time', 'event_code',
    'event_value', 'event_sample', 'event_type',
    'value', 'sample', 'duration', 'onset', 'HED',
]
