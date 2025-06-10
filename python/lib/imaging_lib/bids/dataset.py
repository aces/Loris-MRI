import os
import re
from collections.abc import Iterator
from functools import cached_property

from bids import BIDSLayout

from lib.imaging_lib.bids.dataset_description import BidsDatasetDescription
from lib.imaging_lib.bids.tsv_participants import BidsTsvParticipant, read_bids_participants_tsv_file
from lib.imaging_lib.bids.tsv_scans import BidsTsvScan, read_bids_scans_tsv_file
from lib.imaging_lib.nifti import find_dir_nifti_names
from lib.util.fs import replace_file_extension, search_dir_file_with_regex
from lib.util.iter import find

PYBIDS_IGNORE = ['code', 'sourcedata', 'log', '.git']

PYBIDS_FORCE = [re.compile(r"_annotations\.(tsv|json)$")]


class BidsDataset:
    path: str
    validate: bool

    def __init__(self, bids_path: str, validate: bool):
        self.path     = bids_path
        self.validate = validate

    @property
    def sessions(self) -> Iterator['BidsSession']:
        for subject in self.subjects:
            yield from subject.sessions

    @property
    def data_types(self) -> Iterator['BidsDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def niftis(self) -> Iterator['BidsNifti']:
        for data_type in self.data_types:
            yield from data_type.niftis

    @cached_property
    def subjects(self) -> list['BidsSubject']:
        """
        The subject directories found in the BIDS dataset.
        """

        subjects: list[BidsSubject] = []

        for file in os.scandir(self.path):
            subject_match = re.match(r'sub-([a-zA-Z0-9]+)', file.name)
            if subject_match is None:
                continue

            if not os.path.isdir(file):
                continue

            subject_label = subject_match.group(1)
            subjects.append(BidsSubject(self, subject_label))

        return subjects

    def get_dataset_description(self) -> 'BidsDatasetDescription | None':
        """
        Read the BIDS dataset description file of this BIDS dataset. Return `None` if no dataset
        description file is present in the dataset, or raise an exeption if the file is present but
        does contains incorrect data.
        """

        dataset_description_path = os.path.join(self.path, 'dataset_description.json')
        if not os.path.exists(dataset_description_path):
            return None

        return BidsDatasetDescription(dataset_description_path)

    @cached_property
    def tsv_participants(self) -> dict[str, BidsTsvParticipant] | None:
        """
        The set of participants in the 'participants.tsv' file of this BIDS dataset if it is
        present. This property might raise an exception if the file is present but incorrect.
        """

        tsv_participants_path = os.path.join(self.path, 'participants.tsv')
        if not os.path.exists(tsv_participants_path):
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

    def get_subject(self, subject_label: str) -> 'BidsSubject | None':
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


class BidsSubject:
    root_dataset: BidsDataset
    label: str
    path: str

    def __init__(self, root_dataset: BidsDataset, label: str):
        self.root_dataset = root_dataset
        self.label = label
        self.path = os.path.join(self.root_dataset.path, f'sub-{self.label}')

    @property
    def data_types(self) -> Iterator['BidsDataType']:
        for session in self.sessions:
            yield from session.data_types

    @property
    def niftis(self) -> Iterator['BidsNifti']:
        for data_type in self.data_types:
            yield from data_type.niftis

    @cached_property
    def sessions(self) -> list['BidsSession']:
        """
        The session directories found in this subject directory.
        """

        sessions: list[BidsSession] = []

        for file in os.scandir(self.path):
            if not os.path.isdir(file):
                continue

            session_match = re.match(r'ses-([a-zA-Z0-9]+)', file.name)
            if session_match is None:
                continue

            session_label = session_match.group(1)
            sessions.append(BidsSession(self, session_label))

        if sessions == []:
            sessions.append(BidsSession(self, None))

        return sessions

    def get_session(self, session_label: str) -> 'BidsSession | None':
        """
        Get a session directory of this subject directory or `None` if it does not exist.
        """

        return find(lambda session: session.label == session_label, self.sessions)


class BidsSession:
    subject: BidsSubject
    label: str | None
    path: str
    tsv_scans_path: str | None

    def __init__(self, subject: BidsSubject, label: str | None):
        self.subject = subject
        self.label = label
        if label is None:
            self.path = self.subject.path
        else:
            self.path = os.path.join(self.subject.path, f'ses-{self.label}')

        tsv_scans_name = search_dir_file_with_regex(self.path, r'scans.tsv$')
        if tsv_scans_name is not None:
            self.tsv_scans_path = os.path.join(self.path, tsv_scans_name)
        else:
            self.tsv_scans_path = None

    @property
    def root_dataset(self) -> BidsDataset:
        return self.subject.root_dataset

    @property
    def niftis(self) -> Iterator['BidsNifti']:
        for data_type in self.data_types:
            yield from data_type.niftis

    @cached_property
    def data_types(self) -> list['BidsDataType']:
        """
        The data type directories found in this session directory.
        """

        data_types: list[BidsDataType] = []

        for file in os.scandir(self.path):
            if not os.path.isdir(file):
                continue

            data_types.append(BidsDataType(self, file.name))

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


class BidsDataType:
    session: BidsSession
    name: str
    path: str

    def __init__(self, session: BidsSession, name: str):
        self.session = session
        self.name = name
        self.path = os.path.join(self.session.path, self.name)

    @property
    def root_dataset(self) -> BidsDataset:
        return self.session.root_dataset

    @property
    def subject(self) -> BidsSubject:
        return self.session.subject

    @cached_property
    def niftis(self) -> list['BidsNifti']:
        """
        The NIfTI files found in this data type directory.
        """

        niftis: list[BidsNifti] = []

        for nifti_name in find_dir_nifti_names(self.path):
            niftis.append(BidsNifti(self, nifti_name))

        return niftis


class BidsNifti:
    data_type: BidsDataType
    name: str
    path: str
    suffix: str | None

    def __init__(self, data_type: BidsDataType, name: str):
        self.data_type = data_type
        self.path = os.path.join(self.data_type.path, name)
        self.name = name

        suffix_match = re.search(r'_([a-zA-Z0-9]+)\.nii(\.gz)?$', self.name)
        if suffix_match is not None:
            self.suffix = suffix_match.group(1)
        else:
            self.suffix = None

    @property
    def root_dataset(self) -> BidsDataset:
        return self.data_type.root_dataset

    @property
    def subject(self) -> BidsSubject:
        return self.data_type.subject

    @property
    def session(self) -> BidsSession:
        return self.data_type.session

    def get_json_path(self) -> str | None:
        """
        Get the JSON sidecar file path of this NIfTI file if it exists.
        """

        json_name = replace_file_extension(self.name, 'json')
        json_path = os.path.join(self.data_type.path, json_name)
        if not os.path.exists(json_path):
            return None

        return json_path

    def get_bval_path(self) -> str | None:
        """
        Get the BVAL file path of this NIfTI file if it exists.
        """

        bval_name = replace_file_extension(self.name, 'bval')
        bval_path = os.path.join(self.data_type.path, bval_name)
        if not os.path.exists(bval_path):
            return None

        return bval_path

    def get_bvec_path(self) -> str | None:
        """
        Get the BVEC file path of this NIfTI file if it exists.
        """

        bvec_name = replace_file_extension(self.name, 'bvec')
        bvec_path = os.path.join(self.data_type.path, bvec_name)
        if not os.path.exists(bvec_path):
            return None

        return bvec_path
