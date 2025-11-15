from pathlib import Path
from typing import Literal

from pydantic import ConfigDict, Field

from loris_bids_reader.json_file import BIDSJSONFile
from loris_bids_reader.models import BIDSBaseModel

# Enums for constrained string fields
MRACQUISITION_TYPE = Literal["1D", "2D", "3D"]
PHASE_ENCODING_DIRECTION = Literal["i", "i-", "j", "j-", "k", "k-"]
SLICE_ENCODING_DIRECTION = Literal["i", "i-", "j", "j-", "k", "k-"]
MT_PULSE_SHAPE = Literal["HARD", "GAUSSIAN", "GAUSSHANN", "SINC", "SINCHANN", "SINCGAUSS", "FERMI"]
SPOILING_TYPE = Literal["RF", "GRADIENT", "COMBINED"]


class DeidentificationCodeObject(BIDSBaseModel):
    """Model for deidentification code sequence objects."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
        validate_assignment=True,
        populate_by_name=True,
    )

    code_value: str = Field(..., alias="CodeValue")
    code_meaning: str = Field(..., alias="CodeMeaning")
    coding_scheme_designator: str = Field(..., alias="CodingSchemeDesignator")
    coding_scheme_version: str | None = Field(None, alias="CodingSchemeVersion")


class BIDSMRISidecar(BIDSBaseModel):
    """
    Model for a BIDS MRI sidecar JSON data.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetic-resonance-imaging-data.html
    """

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
        validate_assignment=True,
        populate_by_name=True,
    )

    # HARDWARE INFORMATION FIELDS
    # RECOMMENDED fields
    manufacturer                 : str | None   = Field(None, alias="Manufacturer")
    manufacturers_model_name     : str | None   = Field(None, alias="ManufacturersModelName")
    device_serial_number         : str | None   = Field(None, alias="DeviceSerialNumber")
    station_name                 : str | None   = Field(None, alias="StationName")
    software_versions            : str | None   = Field(None, alias="SoftwareVersions")
    magnetic_field_strength      : float | None = Field(None, gt=0, alias="MagneticFieldStrength")
    receive_coil_name            : str | None   = Field(None, alias="ReceiveCoilName")
    receive_coil_active_elements : str | None   = Field(None, alias="ReceiveCoilActiveElements")
    matrix_coil_mode             : str | None   = Field(None, alias="MatrixCoilMode")
    coil_combination_method      : str | None   = Field(None, alias="CoilCombinationMethod")

    # DEPRECATED field
    hardcopy_device_software_version: str | None = Field(None, alias="HardcopyDeviceSoftwareVersion")

    # OPTIONAL fields
    number_receive_coil_active_elements  : int | None         = Field(None, ge=1, alias="NumberReceiveCoilActiveElements")
    gradient_set_type                    : str | None         = Field(None, alias="GradientSetType")
    mr_transmit_coil_sequence            : str | None         = Field(None, alias="MRTransmitCoilSequence")
    number_transmit_coil_active_elements : int | None         = Field(None, ge=1, alias="NumberTransmitCoilActiveElements")
    table_position                       : list[float] | None = Field(None, min_length=3, max_length=3, alias="TablePosition")

    # INSTITUTION INFORMATION
    # RECOMMENDED fields
    institution_name              : str | None = Field(None, alias="InstitutionName")
    institution_address           : str | None = Field(None, alias="InstitutionAddress")
    institutional_department_name : str | None = Field(None, alias="InstitutionalDepartmentName")

    # SEQUENCE SPECIFICS
    # RECOMMENDED fields
    pulse_sequence_type           : str | None                = Field(None, alias="PulseSequenceType")
    scanning_sequence             : str | list[str] | None    = Field(None, alias="ScanningSequence")
    sequence_variant              : str | list[str] | None    = Field(None, alias="SequenceVariant")
    sequence_name                 : str | None                = Field(None, alias="SequenceName")
    pulse_sequence_details        : str | None                = Field(None, alias="PulseSequenceDetails")
    nonlinear_gradient_correction : bool | None               = Field(None, alias="NonlinearGradientCorrection")
    mr_acquisition_type           : MRACQUISITION_TYPE | None = Field(None, alias="MRAcquisitionType")

    # OPTIONAL fields
    scan_options                : str | list[str] | None     = Field(None, alias="ScanOptions")
    mt_state                    : bool | None                = Field(None, alias="MTState")
    mt_offset_frequency         : float | None               = Field(None, alias="MTOffsetFrequency")
    mt_pulse_bandwidth          : float | None               = Field(None, gt=0, alias="MTPulseBandwidth")
    mt_number_of_pulses         : int | None                 = Field(None, ge=0, alias="MTNumberOfPulses")
    mt_pulse_shape              : MT_PULSE_SHAPE | None      = Field(None, alias="MTPulseShape")
    mt_pulse_duration           : float | None               = Field(None, gt=0, alias="MTPulseDuration")
    number_shots                : float | list[float] | None = Field(None, alias="NumberShots")
    spoiling_state              : bool | None                = Field(None, alias="SpoilingState")
    spoiling_type               : SPOILING_TYPE | None       = Field(None, alias="SpoilingType")
    spoiling_rf_phase_increment : float | None               = Field(None, alias="SpoilingRFPhaseIncrement")
    spoiling_gradient_moment    : float | None               = Field(None, alias="SpoilingGradientMoment")
    spoiling_gradient_duration  : float | None               = Field(None, gt=0, alias="SpoilingGradientDuration")
    water_suppression           : bool | None                = Field(None, alias="WaterSuppression")
    water_suppression_technique : str | None                 = Field(None, alias="WaterSuppressionTechnique")
    b0_shimming_technique       : str | None                 = Field(None, alias="B0ShimmingTechnique")
    b1_shimming_technique       : str | None                 = Field(None, alias="B1ShimmingTechnique")

    # IN- AND OUT-OF-PLANE SPATIAL ENCODING
    # OPTIONAL but RECOMMENDED fields
    parallel_reduction_factor_in_plane     : float | None = Field(None, gt=0, alias="ParallelReductionFactorInPlane")
    parallel_reduction_factor_out_of_plane : float | None = Field(None, gt=0, alias="ParallelReductionFactorOutOfPlane")

    # OPTIONAL fields
    parallel_acquisition_technique : str | None                      = Field(None, alias="ParallelAcquisitionTechnique")
    partial_fourier                : float | None                    = Field(None, gt=0, lt=1, alias="PartialFourier")
    partial_fourier_direction      : str | None                      = Field(None, alias="PartialFourierDirection")
    effective_echo_spacing         : float | None                    = Field(None, gt=0, alias="EffectiveEchoSpacing")
    mixing_time                    : float | None                    = Field(None, gt=0, alias="MixingTime")
    phase_encoding_direction       : PHASE_ENCODING_DIRECTION | None = Field(None, alias="PhaseEncodingDirection")
    total_readout_time             : float | None                    = Field(None, gt=0, alias="TotalReadoutTime")

    # TIMING PARAMETERS
    # RECOMMENDED fields
    echo_time    : float | list[float] | None = Field(None, gt=0, alias="EchoTime")
    dwell_time   : float | None               = Field(None, gt=0, alias="DwellTime")
    slice_timing : list[float] | None         = Field(None, alias="SliceTiming")

    # OPTIONAL fields
    inversion_time           : float | None                    = Field(None, gt=0, alias="InversionTime")
    acquisition_duration     : float | None                    = Field(None, gt=0, alias="AcquisitionDuration")
    slice_encoding_direction : SLICE_ENCODING_DIRECTION | None = Field(None, alias="SliceEncodingDirection")

    # RF & CONTRAST
    # RECOMMENDED fields
    flip_angle: float | list[float] | None = Field(None, alias="FlipAngle")

    # OPTIONAL fields
    negative_contrast: bool | None = Field(None, alias="NegativeContrast")

    # SLICE ACCELERATION
    # OPTIONAL fields
    multiband_acceleration_factor: float | None = Field(None, gt=0, alias="MultibandAccelerationFactor")

    # ANATOMICAL LANDMARKS
    # RECOMMENDED fields
    anatomical_landmark_coordinates: dict[str, list[float]] | None = Field(None, alias="AnatomicalLandmarkCoordinates")

    # ECHO-PLANAR IMAGING AND B0 MAPPING
    # RECOMMENDED fields
    b0_field_identifier : str | list[str] | None = Field(None, alias="B0FieldIdentifier")
    b0_field_source     : str | list[str] | None = Field(None, alias="B0FieldSource")

    # TISSUE DESCRIPTION
    # OPTIONAL fields
    body_part                  : str | None = Field(None, alias="BodyPart")
    body_part_details          : str | None = Field(None, alias="BodyPartDetails")
    body_part_details_ontology : str | None = Field(None, alias="BodyPartDetailsOntology")

    # DEIDENTIFICATION INFORMATION
    # OPTIONAL fields
    deidentification_method               : list[str] | None                        = Field(None, alias="DeidentificationMethod")
    deidentification_method_code_sequence : list[DeidentificationCodeObject] | None = Field(None, alias="DeidentificationMethodCodeSequence")


class BIDSMRISidecarFile(BIDSJSONFile[BIDSMRISidecar]):
    """
    Model for a BIDS MRI sidecar JSON file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetic-resonance-imaging-data.html
    """

    def __init__(self, path: Path):
        super().__init__(BIDSMRISidecar, path)
