from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from loris_bids_reader.json_file import BIDSJSONFile

NA            = Literal['n/a']
RecordingType = Literal['continuous', 'epoched', 'discontinuous']
Manufacturer  = Literal['CTF', 'Neuromag/Elekta/MEGIN', 'BTi/4D', 'KIT/Yokogawa', 'ITAB', 'KRISS', 'Other']


class BIDSMEGSidecar(BaseModel):
    """
    Model for a BIDS MEG sidecar JSON data.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#sidecar-json-_megjson
    """

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra='forbid',
        validate_assignment=True,
        populate_by_name=True,
    )

    # REQUIRED fields
    sampling_frequency    : float                          = Field(..., gt=0, alias='SamplingFrequency')
    power_line_frequency  : float | NA                     = Field(..., alias='PowerLineFrequency')
    dewar_position        : str                            = Field(..., alias='DewarPosition')
    software_filters      : dict[str, dict[str, Any]] | NA = Field(..., alias='SoftwareFilters')
    digitized_landmarks   : bool                           = Field(..., alias='DigitizedLandmarks')
    digitized_head_points : bool                           = Field(..., alias='DigitizedHeadPoints')

    # RECOMMENDED fields
    meg_channel_count     : int | None = Field(None, ge=0, alias='MEGChannelCount')
    meg_ref_channel_count : int | None = Field(None, ge=0, alias='MEGREFChannelCount')
    eeg_channel_count     : int | None = Field(None, ge=0, alias='EEGChannelCount')
    ecog_channel_count    : int | None = Field(None, ge=0, alias='ECOGChannelCount')
    seeg_channel_count    : int | None = Field(None, ge=0, alias='SEEGChannelCount')
    eog_channel_count     : int | None = Field(None, ge=0, alias='EOGChannelCount')
    ecg_channel_count     : int | None = Field(None, ge=0, alias='ECGChannelCount')
    emg_channel_count     : int | None = Field(None, ge=0, alias='EMGChannelCount')
    misc_channel_count    : int | None = Field(None, ge=0, alias='MiscChannelCount')
    trigger_channel_count : int | None = Field(None, ge=0, alias='TriggerChannelCount')

    # RECOMMENDED recording fields
    recording_duration           : float | None                          = Field(None, ge=0, alias='RecordingDuration')
    recording_type               : RecordingType | None                  = Field(None, alias='RecordingType')
    epoch_length                 : float | None                          = Field(None, ge=0, alias='EpochLength')
    continuous_head_localization : bool | None                           = Field(None, alias='ContinuousHeadLocalization')
    head_coil_frequency          : list[float] | float | None            = Field(None, alias='HeadCoilFrequency')
    max_movement                 : float | None                          = Field(None, ge=0, alias='MaxMovement')
    subject_artefact_description : str | NA | None                       = Field(None, alias='SubjectArtefactDescription')
    associated_empty_room        : list[str] | str | None                = Field(None, alias='AssociatedEmptyRoom')
    hardware_filters             : dict[str, dict[str, Any]] | NA | None = Field(None, alias='HardwareFilters')

    # OPTIONAL electrical stimulation fields
    electrical_stimulation            : bool | None = Field(None, alias='ElectricalStimulation')
    electrical_stimulation_parameters : str | None  = Field(None, alias='ElectricalStimulationParameters')

    # RECOMMENDED hardware information fields
    manufacturer             : Manufacturer | None = Field(None, alias='Manufacturer')
    manufacturers_model_name : str | None          = Field(None, alias='ManufacturersModelName')
    software_versions        : str | None          = Field(None, alias='SoftwareVersions')
    device_serial_number     : str | None          = Field(None, alias='DeviceSerialNumber')

    # REQUIRED and RECOMMENDED task information fields
    task_name        : str        = Field(..., alias='TaskName')
    task_description : str | None = Field(None, alias='TaskDescription')
    instructions     : str | None = Field(None, alias='Instructions')
    cog_atlas_id     : str | None = Field(None, alias='CogAtlasID')
    cog_po_id        : str | None = Field(None, alias='CogPOID')

    # RECOMMENDED institution information fields
    institution_name              : str | None = Field(None, alias='InstitutionName')
    institution_address           : str | None = Field(None, alias='InstitutionAddress')
    institutional_department_name : str | None = Field(None, alias='InstitutionalDepartmentName')

    # OPTIONAL EEG-specific fields (if recorded with MEG)
    eeg_placement_scheme         : str | None = Field(None, alias='EEGPlacementScheme')
    cap_manufacturer             : str | None = Field(None, alias='CapManufacturer')
    cap_manufacturers_model_name : str | None = Field(None, alias='CapManufacturersModelName')
    eeg_reference                : str | None = Field(None, alias='EEGReference')


class BIDSMEGSidecarFile(BIDSJSONFile[BIDSMEGSidecar]):
    """
    Model for a BIDS MEG sidecar JSON file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#sidecar-json-_megjson
    """

    def __init__(self, path: Path):
        super().__init__(BIDSMEGSidecar, path)
