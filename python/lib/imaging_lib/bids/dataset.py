import re
from collections.abc import Iterator
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from bids import BIDSLayout

from lib.imaging_lib.bids.dataset_description import BidsDatasetDescription
from lib.imaging_lib.bids.tsv_participants import BidsTsvParticipant, read_bids_participants_tsv_file
from lib.imaging_lib.bids.tsv_scans import BidsTsvScan, read_bids_scans_tsv_file
from lib.util.fs import search_dir_file_with_regex
from lib.util.iter import find

if TYPE_CHECKING:
    from lib.imaging_lib.bids.eeg.dataset import BIDSEEGDataType
    from lib.imaging_lib.bids.mri.dataset import BIDSMRIDataType, BIDSNifti


PYBIDS_IGNORE = ['code', 'sourcedata', 'log', '.git']

PYBIDS_FORCE = [re.compile(r"_annotations\.(tsv|json)$")]


class BIDSDataset:
    path: Path
    validate: bool

    def __init__(self, bids_path: Path, validate: bool):
        self.path     = bids_path
        self.validate = validate

    @property
    def sessions(self) -> Iterator['BIDSSession']:
        for subject in self.subjects:
            yield from subject.sessions

    @property
    def data_types(self) -> Iterator['BIDSDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def niftis(self) -> Iterator['BIDSNifti']:
        from lib.imaging_lib.bids.mri.dataset import BIDSMRIDataType
        for data_type in self.data_types:
            if isinstance(data_type, BIDSMRIDataType):
                yield from data_type.niftis

    @cached_property
    def subjects(self) -> list['BIDSSubject']:
        """
        The subject directories found in the BIDS dataset.
        """

        subjects: list[BIDSSubject] = []

        for file in self.path.iterdir():
            subject_match = re.match(r'sub-([a-zA-Z0-9]+)', file.name)
            if subject_match is None:
                continue

            if not file.is_dir():
                continue

            subject_label = subject_match.group(1)
            subjects.append(BIDSSubject(self, subject_label))

        return subjects

    def get_dataset_description(self) -> 'BidsDatasetDescription | None':
        """
        Read the BIDS dataset description file of this BIDS dataset. Return `None` if no dataset
        description file is present in the dataset, or raise an exeption if the file is present but
        does contains incorrect data.
        """

        dataset_description_path = self.path / 'dataset_description.json'
        if not dataset_description_path.exists():
            return None

        return BidsDatasetDescription(dataset_description_path)

    @cached_property
    def tsv_participants(self) -> dict[str, BidsTsvParticipant] | None:
        """
        The set of participants in the 'participants.tsv' file of this BIDS dataset if it is
        present. This property might raise an exception if the file is present but incorrect.
        """

        tsv_participants_path = self.path / 'participants.tsv'
        if not tsv_participants_path.exists():
            return None

        return read_bids_participants_tsv_file(tsv_participants_path)

    @cached_property
    def subject_labels(self) -> list[str]:
        """
        All the subject labels found in the BIDS dataset.
        """

        subject_labels = list(set(subject.label for subject in self.subjects))
        subject_labels.sort()
        return subject_labels

    @cached_property
    def session_labels(self) -> list[str]:
        """
        All the session labels found in this BIDS dataset.
        """

        session_labels = list(set(session.label for session in self.sessions if session.label is not None))
        session_labels.sort()
        return session_labels

    def get_subject(self, subject_label: str) -> 'BIDSSubject | None':
        """
        Get the subject directory corresponding to a subject label in this BIDS dataset or `None`
        if it does not exist.
        """

        return find(lambda subject: subject.label == subject_label, self.subjects)

    def get_tsv_participant(self, participant_id: str) -> 'BidsTsvParticipant | None':
        """
        Get the `participants.tsv` record corresponding to a participant ID in this BIDS dataset
        or `None` if it does not exist.
        """

        if self.tsv_participants is None:
            return None

        return self.tsv_participants.get(participant_id)

    @cached_property
    def layout(self) -> BIDSLayout:
        """
        Get the PyBIDS BIDSLayout for the BIDS dataset.
        """

        return BIDSLayout(
            root        = self.path,
            ignore      = PYBIDS_IGNORE,
            force_index = PYBIDS_FORCE,
            derivatives = True,
            validate    = self.validate
        )


class BIDSSubject:
    root_dataset: BIDSDataset
    path: Path
    label: str

    def __init__(self, root_dataset: BIDSDataset, label: str):
        self.root_dataset = root_dataset
        self.label = label
        self.path  = self.root_dataset.path / f'sub-{self.label}'

    @property
    def data_types(self) -> Iterator['BIDSDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def niftis(self) -> Iterator['BIDSNifti']:
        from lib.imaging_lib.bids.mri.dataset import BIDSMRIDataType
        for data_type in self.data_types:
            if isinstance(data_type, BIDSMRIDataType):
                yield from data_type.niftis

    @cached_property
    def sessions(self) -> list['BIDSSession']:
        """
        The session directories found in this subject directory.
        """

        sessions: list[BIDSSession] = []

        for file in self.path.iterdir():
            if not file.is_dir():
                continue

            session_match = re.match(r'ses-([a-zA-Z0-9]+)', file.name)
            if session_match is None:
                continue

            session_label = session_match.group(1)
            sessions.append(BIDSSession(self, session_label))

        if sessions == []:
            sessions.append(BIDSSession(self, None))

        return sessions

    def get_session(self, session_label: str) -> 'BIDSSession | None':
        """
        Get a session directory of this subject directory or `None` if it does not exist.
        """

        return find(lambda session: session.label == session_label, self.sessions)


class BIDSSession:
    subject: BIDSSubject
    path: Path
    label: str | None
    tsv_scans_path: Path | None

    def __init__(self, subject: BIDSSubject, label: str | None):
        self.subject = subject
        self.label = label
        if label is not None:
            self.path = subject.path / f'ses-{self.label}'
        else:
            self.path = subject.path

        self.tsv_scans_path = search_dir_file_with_regex(self.path, r'scans.tsv$')

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.subject.root_dataset

    @property
    def niftis(self) -> Iterator['BIDSNifti']:
        for data_type in self.mri_data_types:
            yield from data_type.niftis

    @cached_property
    def mri_data_types(self) -> list['BIDSMRIDataType']:
        """
        The MRI data type directories found in this session directory.
        """

        from lib.imaging_lib.bids.mri.dataset import BIDSMRIDataType

        data_types: list[BIDSMRIDataType] = []

        for data_type_name in ['anat', 'dwi', 'fmap', 'func']:
            data_type_path = self.path / data_type_name
            if data_type_path.is_dir():
                data_types.append(BIDSMRIDataType(self, data_type_name))

        return data_types

    @cached_property
    def eeg_data_types(self) -> list['BIDSEEGDataType']:
        """
        The MRI data type directories found in this session directory.
        """

        from lib.imaging_lib.bids.eeg.dataset import BIDSEEGDataType

        data_types: list[BIDSEEGDataType] = []

        for data_type_name in ['eeg', 'ieeg']:
            data_type_path = self.path / data_type_name
            if data_type_path.is_dir():
                data_types.append(BIDSEEGDataType(self, data_type_name))

        return data_types

    @property
    def data_types(self) -> Iterator['BIDSDataType']:
        """
        The data type directories found in this session directory.
        """

        yield from self.mri_data_types
        yield from self.eeg_data_types

    @cached_property
    def tsv_scans(self) -> dict[str, BidsTsvScan] | None:
        """
        The set of scans in the 'scans.tsv' file of this BIDS directory if it is present. This
        property might raise an exception if the file is present but incorrect.
        """

        if self.tsv_scans_path is None:
            return None

        return read_bids_scans_tsv_file(self.tsv_scans_path)

    def get_tsv_scan(self, file_name: str) -> 'BidsTsvScan | None':
        """
        Get the `scans.tsv` record corresponding to a file name of this session directory or `None`
        if it does not exist.
        """

        if self.tsv_scans is None:
            return None

        return self.tsv_scans.get(file_name)


class BIDSDataType:
    session: BIDSSession
    path: Path

    def __init__(self, session: BIDSSession, name: str):
        self.session = session
        self.path    = session.path / name

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.session.root_dataset

    @property
    def subject(self) -> BIDSSubject:
        return self.session.subject
