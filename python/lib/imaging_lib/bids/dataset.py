import re
from collections.abc import Iterator
from functools import cached_property
from pathlib import Path

from bids import BIDSLayout

from lib.imaging_lib.bids.dataset_description import BidsDatasetDescription
from lib.imaging_lib.bids.tsv_participants import BidsTsvParticipant, read_bids_participants_tsv_file
from lib.imaging_lib.bids.tsv_scans import BidsTsvScan, read_bids_scans_tsv_file
from lib.imaging_lib.nifti import find_dir_nifti_files
from lib.util.fs import replace_file_extension, search_dir_file_with_regex
from lib.util.iter import find

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
        for data_type in self.data_types:
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
        for data_type in self.data_types:
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
        for data_type in self.data_types:
            yield from data_type.niftis

    @cached_property
    def data_types(self) -> list['BIDSDataType']:
        """
        The data type directories found in this session directory.
        """

        data_types: list[BIDSDataType] = []

        for file in self.path.iterdir():
            if not file.is_dir():
                continue

            data_types.append(BIDSDataType(self, file.name))

        return data_types

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

    @cached_property
    def niftis(self) -> list['BIDSNifti']:
        """
        The NIfTI files found in this data type directory.
        """

        niftis: list[BIDSNifti] = []

        for nifti_path in find_dir_nifti_files(self.path):
            niftis.append(BIDSNifti(self, nifti_path.name))

        return niftis


class BIDSNifti:
    data_type: BIDSDataType
    path: Path
    suffix: str | None

    def __init__(self, data_type: BIDSDataType, name: str):
        self.data_type = data_type
        self.path      = data_type.path / name

        suffix_match = re.search(r'_([a-zA-Z0-9]+)\.nii(\.gz)?$', self.name)
        if suffix_match is not None:
            self.suffix = suffix_match.group(1)
        else:
            self.suffix = None

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

    def get_json_path(self) -> Path | None:
        """
        Get the JSON sidecar file path of this NIfTI file if it exists.
        """

        json_name = replace_file_extension(self.name, 'json')
        json_path = self.data_type.path / json_name
        if not json_path.exists():
            return None

        return json_path

    def get_bval_path(self) -> Path | None:
        """
        Get the BVAL file path of this NIfTI file if it exists.
        """

        bval_name = replace_file_extension(self.name, 'bval')
        bval_path = self.data_type.path / bval_name
        if not bval_path.exists():
            return None

        return bval_path

    def get_bvec_path(self) -> Path | None:
        """
        Get the BVEC file path of this NIfTI file if it exists.
        """

        bvec_name = replace_file_extension(self.name, 'bvec')
        bvec_path = self.data_type.path / bvec_name
        if not bvec_path.exists():
            return None

        return bvec_path
