import re
from abc import ABC, abstractmethod
from collections.abc import Iterator, Sequence
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from bids import BIDSLayout
from lib.util.fs import search_dir_file_with_regex
from lib.util.iter import find

from loris_bids_reader.files.dataset_description import BidsDatasetDescriptionJsonFile
from loris_bids_reader.files.participants import BidsParticipantsTsvFile
from loris_bids_reader.files.scans import BidsScansTsvFile
from loris_bids_reader.json import BidsJsonFile

if TYPE_CHECKING:
    from loris_bids_reader.eeg.data_type import BidsEegDataType
    from loris_bids_reader.meg.data_type import BidsMegDataType
    from loris_bids_reader.mri.data_type import BidsMriDataType


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
    def data_types(self) -> Iterator['BidsDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def acquisitions(self) -> Iterator['BidsAcquisition']:
        for data_type in self.data_types:
            yield from data_type.acquisitions

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

    def get_dataset_description(self) -> BidsDatasetDescriptionJsonFile | None:
        """
        Read the BIDS dataset description file of this BIDS dataset. Return `None` if no dataset
        description file is present in the dataset, or raise an exeption if the file is present but
        does contains incorrect data.
        """

        dataset_description_path = self.path / 'dataset_description.json'
        if not dataset_description_path.exists():
            return None

        return BidsDatasetDescriptionJsonFile(dataset_description_path)

    @cached_property
    def tsv_participants(self) -> BidsParticipantsTsvFile | None:
        participants_tsv_path = self.path / 'participants.tsv'
        if not participants_tsv_path.exists():
            return None

        return BidsParticipantsTsvFile(participants_tsv_path)

    @cached_property
    def json_events(self) -> BidsJsonFile | None:
        events_json_path = self.path / 'events.json'
        if not events_json_path.exists():
            return None

        return BidsJsonFile(events_json_path)

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

        return find(self.subjects, lambda subject: subject.label == subject_label)

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
    def data_types(self) -> Iterator['BidsDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def acquisitions(self) -> Iterator['BidsAcquisition']:
        for data_type in self.data_types:
            yield from data_type.acquisitions

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

        return find(self.sessions, lambda session: session.label == session_label)


class BIDSSession:
    subject: BIDSSubject
    path: Path
    label: str | None

    def __init__(self, subject: BIDSSubject, label: str | None):
        self.subject = subject
        self.label = label
        if label is not None:
            self.path = subject.path / f'ses-{self.label}'
        else:
            self.path = subject.path

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.subject.root_dataset

    @property
    def acquisitions(self) -> Iterator['BidsAcquisition']:
        for data_type in self.mri_data_types:
            yield from data_type.acquisitions

    @cached_property
    def mri_data_types(self) -> list['BidsMriDataType']:
        """
        The MRI data type directories found in this session directory.
        """

        from loris_bids_reader.mri.data_type import BidsMriDataType

        data_types: list[BidsMriDataType] = []

        for data_type_name in ['anat', 'dwi', 'fmap', 'func']:
            data_type_path = self.path / data_type_name
            if data_type_path.is_dir():
                data_types.append(BidsMriDataType(self, data_type_name))

        return data_types

    @cached_property
    def eeg_data_types(self) -> list['BidsEegDataType']:
        """
        The MRI data type directories found in this session directory.
        """

        from loris_bids_reader.eeg.data_type import BidsEegDataType

        data_types: list[BidsEegDataType] = []

        for data_type_name in ['eeg', 'ieeg']:
            data_type_path = self.path / data_type_name
            if data_type_path.is_dir():
                data_types.append(BidsEegDataType(self, data_type_name))

        return data_types

    @property
    def data_types(self) -> Iterator['BidsDataType']:
        """
        The data type directories found in this session directory.
        """

        yield from self.mri_data_types
        yield from self.eeg_data_types
        if self.meg is not None:
            yield self.meg

    @cached_property
    def meg(self) -> 'BidsMegDataType | None':
        """
        The MEG data type directory found in this session directory, if there is one.
        """

        from loris_bids_reader.meg.data_type import BidsMegDataType

        meg_data_type_path = self.path / 'meg'
        if not meg_data_type_path.exists():
            return None

        return BidsMegDataType(self, 'meg')

    @cached_property
    def tsv_scans(self) -> BidsScansTsvFile | None:
        tsv_scans_path = search_dir_file_with_regex(self.path, r'scans.tsv$')
        if tsv_scans_path is None:
            return None

        return BidsScansTsvFile(tsv_scans_path)


class BidsDataType(ABC):
    session: BIDSSession
    path: Path

    def __init__(self, session: BIDSSession, name: str):
        self.session = session
        self.path    = session.path / name

    @cached_property
    @abstractmethod
    def acquisitions(self) -> Sequence['BidsAcquisition']:
        ...

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.session.root_dataset

    @property
    def subject(self) -> BIDSSubject:
        return self.session.subject


class BidsAcquisition(ABC):
    data_type: BidsDataType
    path: Path

    def __init__(self, data_type: BidsDataType, name: str):
        self.data_type = data_type
        self.path      = data_type.path / name

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def root_dataset(self) -> BIDSDataset:
        return self.data_type.root_dataset

    @property
    def subject(self) -> BIDSSubject:
        return self.data_type.subject

    @property
    def session(self) -> BIDSSession:
        return self.data_type.session
