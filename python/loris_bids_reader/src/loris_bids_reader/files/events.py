from decimal import Decimal
from pathlib import Path

from loris_utils.iter import map_non_none
from loris_utils.parse import try_parse_decimal

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsEventTsvRow(BidsTsvRow):
    """
    Class representing a BIDS events.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html
    """

    onset: Decimal | None
    duration: Decimal | None
    response_time: Decimal | None
    event_code: int | None
    event_value: str | None
    event_sample: int | None
    event_type: str | None
    trial_type: str | None

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)

        # nullify not present optional cols
        for field in OPTIONAL_EVENT_FIELDS:
            if field not in data.keys():
                data[field] = None

        self.onset = map_non_none(data.get('onset'), try_parse_decimal)

        self.duration = map_non_none(data.get('duration'), try_parse_decimal)

        self.response_time = map_non_none(data.get('response_time'), try_parse_decimal)

        self.event_code = map_non_none(data.get('event_code'), int)

        if 'event_sample' in data:
            self.event_sample = map_non_none(data['event_sample'], int)
        elif 'sample' in data:
            self.event_sample = map_non_none(data['sample'], int)
        else:
            self.event_sample = None

        if 'event_value' in data:
            self.event_value = data['event_value']
        elif 'value' in data:
            self.event_value = data['value']
        else:
            self.event_value = None

        self.event_type = data.get('event_type')

        self.trial_type = data.get('trial_type')


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
