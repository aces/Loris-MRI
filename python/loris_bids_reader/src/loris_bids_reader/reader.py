import re
from collections.abc import Sequence
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path
from typing import TYPE_CHECKING

from bids import BIDSLayout, BIDSLayoutIndexer

from loris_bids_reader.files.dataset_description import BidsDatasetDescriptionJsonFile
from loris_bids_reader.files.participants import BidsParticipantsTsvFile, BidsParticipantTsvRow
from loris_bids_reader.files.scans import BidsScansTsvFile
from loris_bids_reader.info import BidsDataTypeInfo, BidsSessionInfo, BidsSubjectInfo

# Circular imports
if TYPE_CHECKING:
    from loris_bids_reader.mri.reader import BidsMriDataTypeReader

PYBIDS_IGNORE = ['.git', 'code/', 'log/', 'sourcedata/']
PYBIDS_FORCE_INDEX = [re.compile(r"_annotations\.(tsv|json)$")]


@dataclass
class BidsDatasetReader:
    """
    A hierarchical BIDS dataset reader. This class is a wrapper around PyBIDS that allows to easily
    read a BIDS dataset one directory level at the time.
    """

    layout: BIDSLayout
    """
    The PyBIDS layout object of this BIDS dataset.
    """

    path: Path
    """
    The path of this BIDS dataset.
    """

    def __init__(self, path: Path, validate: bool = True):
        self.path = path
        self.layout = BIDSLayout(
            path,
            validate=validate,
            derivatives=True,
            indexer=BIDSLayoutIndexer(
                ignore=PYBIDS_IGNORE,
                force_index=PYBIDS_FORCE_INDEX,
            ),
        )

    @cached_property
    def dataset_description_file(self) -> BidsDatasetDescriptionJsonFile | None:
        """
        The `dataset_description.json` file of this BIDS dataset, if it exists.
        """

        dataset_description_path = self.path / 'dataset_description.json'
        if not dataset_description_path.is_file():
            return None

        return BidsDatasetDescriptionJsonFile(dataset_description_path)

    @cached_property
    def participants_file(self) -> BidsParticipantsTsvFile | None:
        """
        The `participants.tsv` file of this BIDS dataset, if it exists.
        """

        participants_path = self.path / 'participants.tsv'
        if not participants_path.is_file():
            return None

        return BidsParticipantsTsvFile(participants_path)

    @cached_property
    def subject_labels(self) -> list[str]:
        """
        The subject labels present in this BIDS dataset (without the `sub-` prefix).
        """

        return self.layout.get_subjects()  # type: ignore

    @cached_property
    def session_labels(self) -> list[str]:
        """
        The session labels present in this BIDS dataset (without the `ses-` prefix).
        """

        return self.layout.get_sessions()  # type: ignore

    @cached_property
    def subjects(self) -> list['BidsSubjectReader']:
        """
        Get the subject directory readers of this BIDS dataset.
        """

        return [
            BidsSubjectReader(
                dataset=self,
                label=subject  # type: ignore
            ) for subject in self.layout.get_subjects()  # type: ignore
        ]

    @cached_property
    def sessions(self) -> list['BidsSessionReader']:
        """
        Get the session directory readers of this BIDS dataset.
        """

        return [
            session
            for subject in self.subjects
            for session in subject.sessions
        ]

    @cached_property
    def data_types(self) -> list['BidsDataTypeReader']:
        """
        Get the data type directory readers of this BIDS dataset.
        """

        return [
            data_type
            for subject in self.subjects
            for session in subject.sessions
            for data_type in session.data_types
        ]


@dataclass
class BidsSubjectReader:
    """
    A BIDS subject directory reader.
    """

    dataset: BidsDatasetReader
    """
    The root reader of this BIDS dataset.
    """

    label: str
    """
    The subject label of this directory (without the `sub-` prefix).
    """

    @cached_property
    def participant_row(self) -> BidsParticipantTsvRow | None:
        """
        The row of the `participants.tsv` file corresponding to this subject, if it exists.
        """

        if self.dataset.participants_file is None:
            return None

        return self.dataset.participants_file.get_row(self.label)

    @cached_property
    def sessions(self) -> list['BidsSessionReader']:
        """
        Get the session directory readers of this subject.
        """

        session_labels = self.dataset.layout.get_sessions(subject=self.label)  # type: ignore
        if session_labels == []:
            return [BidsSessionReader(subject=self, label=None)]

        return [
            BidsSessionReader(
                subject=self,
                label=session,  # type: ignore
            ) for session in session_labels  # type: ignore
        ]

    @cached_property
    def data_types(self) -> list['BidsDataTypeReader']:
        """
        Get the data type directory readers of this subject.
        """

        return [
            data_type
            for session in self.sessions
            for data_type in session.data_types
        ]

    @cached_property
    def info(self) -> BidsSubjectInfo:
        """
        The information about this subject directory.
        """

        return BidsSubjectInfo(
            subject         = self.label,
            participant_row = self.participant_row,
        )


@dataclass(frozen=True)
class BidsSessionReader:
    """
    A BIDS session directory reader. For sessionless BIDS datasets, this is also the directory as
    the BIDS subject directory.
    """

    subject: BidsSubjectReader
    """
    The reader of the parent session directory.
    """

    label: str | None
    """
    The session label of this directory (without the `ses-` prefix), or `None` if this is a
    sessionless BIDS dataset.
    """

    @cached_property
    def scans_file(self) -> BidsScansTsvFile | None:
        scans_paths: list[str] = self.subject.dataset.layout.get(  # type: ignore
            subject=self.subject.label,
            session=self.label,
            suffix='scans',
            return_type='filename',
        )

        if scans_paths == []:
            return None

        return BidsScansTsvFile(Path(scans_paths[0]))

    @cached_property
    def mri_data_types(self) -> list['BidsMriDataTypeReader']:
        """
        Get the MRI data type directory readers of this session.
        """

        from loris_bids_reader.mri.reader import BidsMriDataTypeReader

        return [
            BidsMriDataTypeReader(
                session=self,
                name=data_type,  # type: ignore
            ) for data_type in self.subject.dataset.layout.get_datatypes(  # type: ignore
                subject=self.subject.label,
                session=self.label,
                datatype=['anat', 'dwi', 'fmap', 'func'],
            )
        ]

    @cached_property
    def eeg_data_types(self) -> list['BidsDataTypeReader']:
        """
        Get the EEG data type directory readers of this session.
        """

        return [
            BidsDataTypeReader(
                session=self,
                name=data_type,  # type: ignore
            ) for data_type in self.subject.dataset.layout.get_datatypes(  # type: ignore
                subject=self.subject.label,
                session=self.label,
                datatype=['eeg', 'ieeg'],
            )
        ]

    @cached_property
    def data_types(self) -> Sequence['BidsDataTypeReader']:
        """
        Get all the data type directory readers of this session.
        """

        return self.eeg_data_types + self.mri_data_types

    @cached_property
    def info(self) -> BidsSessionInfo:
        """
        The information about this session directory.
        """

        return BidsSessionInfo(
            subject         = self.subject.label,
            participant_row = self.subject.participant_row,
            session         = self.label,
            scans_file      = self.scans_file,
        )


@dataclass
class BidsDataTypeReader:
    """
    A BIDS data type directory reader.
    """

    session: BidsSessionReader
    """
    The reader of the parent session directory.
    """

    name: str
    """
    The data type name of this directory.
    """

    @cached_property
    def info(self) -> BidsDataTypeInfo:
        """
        The information about this data type directory.
        """

        return BidsDataTypeInfo(
            subject         = self.session.subject.label,
            participant_row = self.session.subject.participant_row,
            session         = self.session.label,
            scans_file      = self.session.scans_file,
            data_type       = self.name,
        )
