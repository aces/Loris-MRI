from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

NA            = Literal['n/a']
RecordingType = Literal['continuous', 'epoched', 'discontinuous']
Manufacturer  = Literal['CTF', 'Neuromag/Elekta/MEGIN', 'BTi/4D', 'KIT/Yokogawa', 'ITAB', 'KRISS', 'Other']


class BIDSMEGSidecar(BaseModel):
    """
    Model for the BIDS MEG sidecar JSON file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetoencephalography.html#sidecar-json-_megjson
    """

    # REQUIRED fields
    sampling_frequency    : float                          = Field(..., gt=0)
    power_line_frequency  : float | NA                     = Field(...)
    dewar_position        : str                            = Field(...)
    software_filters      : dict[str, dict[str, Any]] | NA = Field(...)
    digitized_landmarks   : bool                           = Field(...)
    digitized_head_points : bool                           = Field(...)

    # RECOMMENDED fields
    meg_channel_count     : int | None = Field(None, ge=0)
    meg_ref_channel_count : int | None = Field(None, ge=0)
    eeg_channel_count     : int | None = Field(None, ge=0)
    ecog_channel_count    : int | None = Field(None, ge=0)
    seeg_channel_count    : int | None = Field(None, ge=0)
    eog_channel_count     : int | None = Field(None, ge=0)
    ecg_channel_count     : int | None = Field(None, ge=0)
    emg_channel_count     : int | None = Field(None, ge=0)
    misc_channel_count    : int | None = Field(None, ge=0)
    trigger_channel_count : int | None = Field(None, ge=0)

    # RECOMMENDED recording fields
    recording_duration           : float | None                          = Field(None, ge=0)
    recording_type               : RecordingType | None                  = Field(None)
    epoch_length                 : float | None                          = Field(None, ge=0)
    continuous_head_localization : bool | None                           = Field(None)
    head_coil_frequency          : list[float] | float | None            = Field(None)
    max_movement                 : float | None                          = Field(None, ge=0)
    subject_artefact_description : str | NA | None                       = Field(None)
    associated_empty_room        : list[str] | str | None                = Field(None)
    hardware_filters             : dict[str, dict[str, Any]] | NA | None = Field(None)

    # OPTIONAL electrical stimulation fields
    electrical_stimulation            : bool | None = Field(None)
    electrical_stimulation_parameters : str | None  = Field(None)

    # RECOMMENDED hardware information fields
    manufacturer             : Manufacturer | None = Field(None)
    manufacturers_model_name : str | None          = Field(None)
    software_versions        : str | None          = Field(None)
    device_serial_number     : str | None          = Field(None)

    # REQUIRED and RECOMMENDED task information fields
    task_name        : str        = Field(...)
    task_description : str | None = Field(None)
    instructions     : str | None = Field(None)
    cog_atlas_id     : str | None = Field(None)
    cog_po_id        : str | None = Field(None)

    # RECOMMENDED institution information fields
    institution_name              : str | None = Field(None)
    institution_address           : str | None = Field(None)
    institutional_department_name : str | None = Field(None)

    # OPTIONAL EEG-specific fields (if recorded with MEG)
    eeg_placement_scheme         : str | None = Field(None)
    cap_manufacturer             : str | None = Field(None)
    cap_manufacturers_model_name : str | None = Field(None)
    eeg_reference                : str | None = Field(None)

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra='forbid',
        validate_assignment=True,
        populate_by_name=True,
    )
