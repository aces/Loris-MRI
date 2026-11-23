from datetime import datetime
from pathlib import Path
from typing import Any

from loris_utils.iter import map_non_none

from lib.db.models.candidate import DbCandidate
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_protocol_group import DbMriProtocolGroup
from lib.db.models.mri_protocol_violated_scan import DbMriProtocolViolatedScan
from lib.db.queries.mri_protocol_violated_scan import try_get_matching_mri_protocol_violated_scan
from lib.env import Env


def register_mri_protocol_violated_scan(
    env: Env,
    file_path: Path,
    candidate: DbCandidate,
    dicom_archive: DbDicomArchive | None,
    protocol_group: DbMriProtocolGroup | None,
    patient_name: str | None,
    scan_parameters: dict[str, Any],
) -> DbMriProtocolViolatedScan:
    """
    Register a protocol violated scan in the database using the provided information, or return
    the existing scan if it already exists.
    """

    dicom_archive_id = dicom_archive.id if dicom_archive is not None else None
    series_uid = scan_parameters.get('SeriesInstanceUID')
    echo_time = map_non_none(scan_parameters.get('EchoTime'), str)
    echo_number = map_non_none(scan_parameters.get('EchoNumber'), repr)
    phase_direction = scan_parameters.get('PhaseEncodingDirection')

    scan = try_get_matching_mri_protocol_violated_scan(
        env.db, dicom_archive_id, series_uid, echo_time, echo_number, phase_direction,
    )

    if scan is not None:
        return scan

    scan = DbMriProtocolViolatedScan(
        candidate_id             = candidate.id,
        pscid                    = candidate.psc_id,
        dicom_archive_id         = dicom_archive_id,
        time_run                 = datetime.now(),
        patient_name             = patient_name,
        file_path                = file_path,
        protocol_group_id        = protocol_group.id if protocol_group is not None else None,
        series_uid               = series_uid,
        series_description       = scan_parameters.get('SeriesDescription'),
        image_type               = map_non_none(scan_parameters.get('ImageType'), str),
        tr_range                 = map_non_none(scan_parameters.get('RepetitionTime'), str),
        te_range                 = echo_time,
        ti_range                 = map_non_none(scan_parameters.get('InversionTime'), str),
        slice_thickness_range    = map_non_none(scan_parameters.get('SliceThickness'), str),
        xspace_range             = map_non_none(scan_parameters.get('xspace'), str),
        yspace_range             = map_non_none(scan_parameters.get('yspace'), str),
        zspace_range             = map_non_none(scan_parameters.get('zspace'), str),
        xstep_range              = map_non_none(scan_parameters.get('xstep'), str),
        ystep_range              = map_non_none(scan_parameters.get('ystep'), str),
        zstep_range              = map_non_none(scan_parameters.get('zstep'), str),
        time_range               = map_non_none(scan_parameters.get('time'), str),
        echo_number              = echo_number,
        phase_encoding_direction = phase_direction,
    )

    env.db.add(scan)
    env.db.flush()

    return scan
