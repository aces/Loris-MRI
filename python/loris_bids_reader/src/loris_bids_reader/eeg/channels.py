import re
from pathlib import Path
from typing import Any

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsEegChannelTsvRow(BidsTsvRow):
    """
    Class representing a BIDS EEG or iEEG channels.tsv row.

    Documentation:
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html#channels-description-_channelstsv
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/intracranial-electroencephalography.html#channels-description-_channelstsv
    """

    def __init__(self, data: dict[str, Any]):
        super().__init__(data)

        # nullify not present optional cols
        for field in OPTIONAL_CHANNEL_FIELDS:
            if field not in data.keys():
                data[field] = None

        if data['manual'] == 'TRUE':
            data['manual'] = 1
        elif data['manual'] == 'FALSE':
            data['manual'] = 0

        if data['high_cutoff'] == 'Inf':
            # replace 'Inf' by the maximum float value to be stored in the
            # physiological_channel table (a.k.a. 99999.999)
            data['high_cutoff'] = 99999.999

        if data['high_cutoff'] == 'n/a':
            data['high_cutoff'] = None

        if data['low_cutoff'] == 'n/a':
            data['low_cutoff'] = None

        if re.match(r"n.?a", str(data['notch']), re.IGNORECASE):
            # replace n/a, N/A, na, NA by None which will translate to NULL
            # in the physiological_channel table
            data['notch'] = None


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
