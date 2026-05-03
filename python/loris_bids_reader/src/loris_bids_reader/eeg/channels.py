import re
from decimal import Decimal
from pathlib import Path

from loris_utils.iter import map_non_none

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsEegChannelTsvRow(BidsTsvRow):
    """
    Class representing a BIDS EEG or iEEG channels.tsv row.

    Documentation:
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html#channels-description-_channelstsv
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/intracranial-electroencephalography.html#channels-description-_channelstsv
    """

    name: str
    type: str
    unit: str
    description: str | None
    sampling_frequency: Decimal | None
    status: str | None
    status_description: str | None
    low_cutoff: Decimal | None
    high_cutoff: Decimal | None
    manual: Decimal | None
    notch: Decimal | None
    reference: str | None

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)

        match data.get('name'):
            case None:
                raise Exception("Missing channel name in BIDS channel file.")
            case name:
                self.name = name

        match data.get('type'):
            case None:
                raise Exception(f"Missing channel type for channel '{self.name}' in BIDS channel file.")
            case type:
                self.type = type

        match data.get('units'):
            case None:
                raise Exception(f"Missing channel unit for channel '{self.name}' in BIDS channel file.")
            case unit:
                self.unit = unit

        self.description = data.get('description')

        self.sampling_frequency = map_non_none(data.get('sampling_frequency'), Decimal)

        self.status = data.get('status')

        self.status_description = data.get('status_description')

        self.low_cutoff = map_non_none(data.get('low_cutoff'), Decimal)

        match data.get('high_cutoff'):
            case None:
                self.high_cutoff = None
            case 'Inf':
                # Replace infinite with the maximum float value to be stored in the physiological
                # channel table.
                self.high_cutoff = Decimal('999999.999')
            case high_cutoff:
                self.high_cutoff = Decimal(high_cutoff)

        match data.get('manual'):
            case None:
                self.manual = None
            case 'TRUE':
                self.manual = Decimal(1)
            case 'FALSE':
                self.manual = Decimal(0)
            case manual:
                self.manual = Decimal(manual)

        if 'notch' not in data or data['notch'] is None or re.match(r"n.?a", data['notch'], re.IGNORECASE):
            # replace n/a, N/A, na, NA by None which will translate to NULL
            # in the physiological_channel table
            self.notch = None
        else:
            self.notch = Decimal(data['notch'])

        self.reference = data.get('reference')


class BidsEegChannelsTsvFile(BidsTsvFile[BidsEegChannelTsvRow]):
    """
    Class representing a BIDS EEG or iEEG channels.tsv file.

    Documentation:
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html#channels-description-_channelstsv
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/intracranial-electroencephalography.html#channels-description-_channelstsv
    """

    def __init__(self, path: Path):
        super().__init__(BidsEegChannelTsvRow, path)


OPTIONAL_CHANNEL_FIELDS = [
    'description',        'sampling_frequency', 'low_cutoff',
    'high_cutoff',        'manual',             'notch',
    'status_description', 'units',              'reference',
]
