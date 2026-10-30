from dataclasses import dataclass
from typing import NewType

BidsSubjectLabel = NewType('BidsSubjectLabel', str)
"""
A BIDS subject label, without the `sub-` prefix.
"""

BidsSessionLabel = NewType('BidsSessionLabel', str)
"""
A BIDS session label, without the `ses-` prefix.
"""


@dataclass(frozen=True)
class BidsSubjectSessionLabel:
    """
    The BIDS subject and session labels that identify a session directory within a dataset.
    """

    subject: BidsSubjectLabel
    session: BidsSessionLabel | None

    @property
    def display_name(self) -> str:
        """
        Get the prefixed BIDS subject/session name.
        """

        subject_name = f'sub-{self.subject}'
        if self.session is None:
            return subject_name

        return f'{subject_name}/ses-{self.session}'
