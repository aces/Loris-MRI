from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict

from loris_bids_reader.models import WithNA
from loris_bids_reader.tsv_file import BIDSTSVFile

BIDSMEGChannelStatus = Literal['good', 'bad']

BIDSMEGChannelType = Literal[
    'MEGMAG', 'MEGGRADAXIAL', 'MEGGRADPLANAR', 'MEGREFMAG',
    'MEGREFGRADAXIAL', 'MEGREFGRADPLANAR', 'MEGOTHER', 'EEG',
    'ECOG', 'SEEG', 'DBS', 'VEOG', 'HEOG', 'EOG', 'ECG', 'EMG',
    'TRIG', 'AUDIO', 'PD', 'EYEGAZE', 'PUPIL', 'MISC', 'SYSCLOCK',
    'ADC', 'DAC', 'HLU', 'FITERR', 'OTHER'
]


# TODO: Can the annotations of this be factorized using a type alias?

class BIDSMEGChannelRow(BaseModel):
    """
    Model for a BIDS MEG channels TSV file row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#channels-description-_channelstsv
    """

    model_config = ConfigDict(extra='allow', validate_assignment=True)

    # Required fields (must appear in specific order)
    name:  str
    type:  BIDSMEGChannelType
    units: WithNA[str]

    # Optional fields (can appear anywhere)
    description:        str | None                   = None
    sampling_frequency: WithNA[float]                = None
    low_cutoff:         WithNA[float]                = None
    high_cutoff:        WithNA[float]                = None
    notch:              WithNA[float | list[float]]  = None
    software_filters:   WithNA[str]                  = None
    status:             WithNA[BIDSMEGChannelStatus] = None
    status_description: WithNA[str]                  = None


class BIDSMEGChannelsFile(BIDSTSVFile[BIDSMEGChannelRow]):
    """
    Wrapper for a BIDS channels TSV file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#channels-description-_channelstsv
    """

    def __init__(self, path: Path):
        super().__init__(BIDSMEGChannelRow, path)
