from python.lib.dataclass.api import Api


def post_candidate_dicom(api: Api, cand_id: int, psc_id: str, visit_label: str, is_phantom: bool, overwrite: bool):
    data = {
        'CandID':    cand_id,
        'PSCID':     psc_id,
        'Visit':     visit_label,
        'IsPhantom': is_phantom,
    }

    if overwrite:
        headers = {'LORIS-Overwrite': 'overwrite'}
    else:
        headers = {}

    api.call('v0.0.4-dev', f'/candidates/{cand_id}/{visit_label}/dicoms', method='POST', headers=headers, data=data)
    # TODO: Handle 303
