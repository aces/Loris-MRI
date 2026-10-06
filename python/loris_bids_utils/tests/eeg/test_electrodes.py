from pathlib import Path

from loris_bids_utils.eeg.electrodes import BidsEegElectrodesTsvFile


def test_parse_electrodes_file(tmp_path: Path):
    path = tmp_path / 'electrodes.tsv'
    path.write_text(
        'name\tx\ty\tz\ttype\tmaterial\timpedance\n'
        'E1\t1.5\t2\t3\tdepth\tplatinum\t12\n'
        'E2\tn/a\tN/A\tNaN\tn/a\t\tn/a\n'
    )

    electrodes = BidsEegElectrodesTsvFile(path).rows

    assert (electrodes[0].x, electrodes[0].y, electrodes[0].z) == (1.5, 2.0, 3.0)
    assert electrodes[0].type == 'depth'
    assert electrodes[0].material == 'platinum'
    assert electrodes[0].impedance == 12
    assert (electrodes[1].x, electrodes[1].y, electrodes[1].z) == (None, None, None)
    assert electrodes[1].type is None
    assert electrodes[1].material is None
    assert electrodes[1].impedance is None
