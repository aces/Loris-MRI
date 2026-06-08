from dataclasses import dataclass

import mne.io
import numpy as np
from fastapi import HTTPException
from lib.config import get_data_dir_path_config
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from loris_bids_utils.meg.head_shape import MegCtfHeadShapeFile
from mne.io.ctf.ctf import RawCTF
from pydantic import BaseModel


class MegHeadShapePoint(BaseModel):
    x: float
    y: float
    z: float


class MegHeadShapeResponse(BaseModel):
    points: dict[str, MegHeadShapePoint]


def get_meg_head_shape(env: Env, physio_file: DbPhysioFile) -> MegHeadShapeResponse:
    """
    Get head shape points aligned to the MEG sensor coordinate system.
    """

    if physio_file.type != 'ctf':
        raise HTTPException(status_code=404, detail="Electrophysiology file is not an MEG file.")
    if physio_file.head_shape_file is None:
        raise HTTPException(status_code=404, detail="Headshape file not found.")

    data_dir_path = get_data_dir_path_config(env)

    # 1. Read the raw head shape (already in CTF head coordinates, cm → m)
    head_shape_path = data_dir_path / physio_file.head_shape_file.path
    head_shape_file = MegCtfHeadShapeFile.read(head_shape_path)

    # 2. Read the MEG data to get MNE's fiducial positions
    raw_ctf = mne.io.read_raw_ctf(data_dir_path / physio_file.path)  # type: ignore

    # 3. Align head shape to MNE's head coordinates
    aligned_points = align_head_shape_to_mne(head_shape_file, raw_ctf)

    # 4. Return as response
    response_points: dict[str, MegHeadShapePoint] = {}
    for name, point in aligned_points.items():
        response_points[name] = MegHeadShapePoint(
            x = float(point[0]),
            y = float(point[1]),
            z = float(point[2]),
        )

    return MegHeadShapeResponse(points=response_points)


VecF = np.ndarray[tuple[int], np.dtype[np.float64]]


@dataclass
class Fiducials:
    nasion: VecF
    lpa: VecF
    rpa: VecF


def get_mne_raw_fiducials(raw: RawCTF) -> Fiducials:
    positions = raw.get_montage().get_positions()  # type: ignore

    return Fiducials(
        nasion = positions['nasion'],  # type: ignore
        lpa    = positions['lpa'],  # type: ignore
        rpa    = positions['rpa'],  # type: ignore
    )


def get_head_shape_fiducials(head_shape_file: MegCtfHeadShapeFile) -> Fiducials:
    if head_shape_file.nasion is None or head_shape_file.lpa is None or head_shape_file.rpa is None:
        raise Exception("Could not find head shape fiducial points.")

    return Fiducials(
        nasion = head_shape_file.nasion.to_numpy(),
        lpa    = head_shape_file.lpa.to_numpy(),
        rpa    = head_shape_file.rpa.to_numpy(),
    )


def align_head_shape_to_mne(head_shape_file: MegCtfHeadShapeFile, raw_ctf: RawCTF) -> dict[str, VecF]:
    """
    Align head shape points (in CTF head coordinates) to MNE's head coordinates using the three
    cardinal fiducials: Nasion, LPA, RPA.
    """

    # Convert head shape points from centimeters to meters to match MNE units.
    head_shape_file = head_shape_file.scale(1 / 100)

    head_shape_fiducials = get_head_shape_fiducials(head_shape_file)
    mne_fiducials = get_mne_raw_fiducials(raw_ctf)

    # List fiducial points in the same order.
    source_points = np.array([
        head_shape_fiducials.nasion,
        head_shape_fiducials.lpa,
        head_shape_fiducials.rpa,
    ])

    target_points = np.array([
        mne_fiducials.nasion,
        mne_fiducials.lpa,
        mne_fiducials.rpa,
    ])

    # Remove translation.
    source_centroid = np.mean(source_points, axis=0)
    target_centroid = np.mean(target_points, axis=0)
    source_centered = source_points - source_centroid
    target_centered = target_points - target_centroid

    # Compute rotation matrix using SVD (Kabsch algorithm).
    h = source_centered.T @ target_centered
    u, _, vt = np.linalg.svd(h)
    r = vt.T @ u.T

    # Special reflection case.
    if np.linalg.det(r) < 0:
        vt[-1, :] *= -1
        r = vt.T @ u.T

    # Apply transformation to all points.
    aligned_points: dict[str, VecF] = {}
    for name, point in head_shape_file.points.items():
        aligned_points[name] = (r @ (point.to_numpy() - source_centroid)) + target_centroid

    return aligned_points
