import math
import re

import mne_bids
from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from mne_bids import BIDSPath

from lib.db.models.physio_coord_system_electrode import DbPhysioCoordSystemElectrode
from lib.db.models.physio_coord_system_point_3d import DbPhysioCoordSystemPoint3d
from lib.db.models.physio_electrode import DbPhysioElectrode
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.point_3d import DbPoint3D
from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv


def read_meg_channels(env: Env, import_env: BidsImportEnv, physio_file: DbPhysioFile, acquisition: MegAcquisition, bids_info: BidsAcquisitionInfo):
    name = acquisition.ctf_path.name

    bids_path = BIDSPath(
        subject=bids_info.subject,
        session=bids_info.session,
        task=re.search(r'task-([a-zA-Z0-9]+)', name).group(1) if 'task-' in name else None,
        run=re.search(r'run-([0-9]+)', name).group(1) if 'run-' in name else None,
        datatype='meg',
        root=import_env.source_bids_path,
        suffix='meg',
        extension='.ds',
    )

    raw = mne_bids.read_raw_bids(bids_path)
    # MEG sensors positions are in raw.info['chs']
    for ch in raw.info['chs'][:5]:  # First 5 channels
        print(f"Channel: {ch['ch_name']}")
        print(f"  Type: {ch['kind']}")  # kind corresponds to sensor type
        print(f"  Position (loc): {ch['loc'][:3]}")  # First 3 values are x,y,z
        print(f"  Unit: {ch['unit']}")

        loc_x, loc_y, loc_z = float(ch['loc'][0]), float(ch['loc'][1]), float(ch['loc'][2])

        if not (math.isnan(loc_x) or math.isnan(loc_y) or math.isnan(loc_z)):
            point = DbPoint3D(x=loc_x, y=loc_y, z=loc_z)
            env.db.add(point)
            env.db.flush()

            env.db.add(DbPhysioCoordSystemPoint3d(
                coord_system_id=1,  # You would need to determine the correct coordinate system ID to use here
                point_3d_id=point.id,
                name=ch['ch_name'],
            ))

            electrode = DbPhysioElectrode(
                name=ch['ch_name'],
                type_id=None,  # You would need to map ch['kind'] to your channel types in the database
                material_id=None,
                point_3d_id=point.id,  # You would need to create a Point3D entry for the location and use its ID here
                impedance=None,
                file_path=acquisition.channels_file.path if acquisition.channels_file else None,
            )
            env.db.add(electrode)
            env.db.flush()

            env.db.add(DbPhysioCoordSystemElectrode(
                coord_system_id=1,  # You would need to determine the correct coordinate system ID to use here
                electrode_id=electrode.id,
                physio_file_id=physio_file.id,
            ))

            print(f"Electrode inserted with ID {electrode.id}")
        else:
            print("  No position information available for this channel.")
