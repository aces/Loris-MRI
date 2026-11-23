# pyright: reportPrivateUsage=false

from math import isclose
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import func, select

from lib.db.models.bids_category import DbBidsCategory
from lib.db.models.bids_mri_scan_type import DbBidsMriScanType
from lib.db.models.bids_scan_type import DbBidsScanType
from lib.db.models.candidate import DbCandidate
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_candidate_error import DbMriCandidateError
from lib.db.models.mri_protocol_group import DbMriProtocolGroup
from lib.db.models.mri_protocol_violated_scan import DbMriProtocolViolatedScan
from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.queries.bids_mri_scan_type import try_get_bids_mri_scan_type_with_scan_type_id
from lib.env import Env
from lib.imaging_lib.mri_candidate_error import register_mri_candidate_error
from lib.imaging_lib.mri_protocol_violated_scan import register_mri_protocol_violated_scan


@pytest.mark.parametrize('archive_id', [None, 1])
def test_candidate_error_deduplication(env: Env, archive_id: int | None):
    archive = None
    if archive_id is not None:
        archive = DbDicomArchive(
            id=archive_id, study_instance_uid='1.2.3',
            md5_hash_dicom_only='dicom', md5_hash_archive='archive',
            creating_user='test', source_path=Path('source'), path=Path('archive'),
        )
    if archive is not None:
        env.db.add(archive)
    args = (env, 'patient', archive, Path('image.nii'), '1.2.3', 0.01, 'mismatch')
    error = register_mri_candidate_error(*args)
    env.db.commit()
    env.db.expire_all()
    assert register_mri_candidate_error(*args).id == error.id
    assert error.file_path == Path('image.nii')
    assert error.echo_time is not None
    assert isclose(error.echo_time, 0.01)
    assert env.db.scalar(select(func.count()).select_from(DbMriCandidateError)) == 1
    register_mri_candidate_error(env, 'patient', archive, Path('other.nii'), '1.2.3', 0.01, 'other reason')
    assert env.db.scalar(select(func.count()).select_from(DbMriCandidateError)) == 2


@pytest.mark.parametrize('echo_number', [None, 1, [1, 2]])
@pytest.mark.parametrize('group_id', [None, 1])
def test_unknown_protocol_deduplication(env: Env, echo_number: object, group_id: int | None):
    candidate = DbCandidate(id=1, cand_id=111111, psc_id='DCC001',
                            registration_site_id=1, registration_project_id=1)
    env.db.add(candidate)
    parameters: dict[str, Any] = {'SeriesInstanceUID': '1.2.3', 'EchoTime': 0.01,
                  'ImageType': ['ORIGINAL', 'PRIMARY'], 'xspace': 128}
    if echo_number is not None:
        parameters['EchoNumber'] = echo_number
    group = DbMriProtocolGroup(id=group_id, name='protocol') if group_id is not None else None
    if group is not None:
        env.db.add(group)
    args = (env, Path('trashbin/image.nii'), candidate, None, group, 'patient', parameters)
    scan = register_mri_protocol_violated_scan(*args)
    env.db.commit()
    env.db.expire_all()
    assert register_mri_protocol_violated_scan(*args).id == scan.id
    assert scan.candidate_id == candidate.id
    assert scan.pscid == 'DCC001'
    assert scan.protocol_group_id == group_id
    assert scan.te_range == '0.01'
    assert scan.echo_number == (repr(echo_number) if echo_number is not None else None)
    assert scan.image_type == "['ORIGINAL', 'PRIMARY']"
    assert scan.xspace_range == '128'
    assert env.db.scalar(select(func.count()).select_from(DbMriProtocolViolatedScan)) == 1
    parameters['EchoTime'] = 0.02
    register_mri_protocol_violated_scan(*args)
    assert env.db.scalar(select(func.count()).select_from(DbMriProtocolViolatedScan)) == 2


def test_bids_mapping_requires_category_and_suffix(env: Env):
    env.db.add_all([
        DbMriScanType(id=1, name='T1w'),
        DbBidsCategory(id=1, name='anat'),
        DbBidsScanType(id=1, name='T1w'),
        DbBidsMriScanType(scan_type_id=1, category_id=1),
    ])
    assert try_get_bids_mri_scan_type_with_scan_type_id(env.db, 1) is None
    mapping = env.db.get(DbBidsMriScanType, 1)
    assert mapping is not None
    mapping.bids_scan_type_id = 1
    assert try_get_bids_mri_scan_type_with_scan_type_id(env.db, 1) is mapping
    assert mapping.category is not None
    assert mapping.category.name == 'anat'
    assert try_get_bids_mri_scan_type_with_scan_type_id(env.db, 2) is None
