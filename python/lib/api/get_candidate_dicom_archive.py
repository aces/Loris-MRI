from python.lib.dataclass.api import Api


def get_candidate_dicom_archive(api: Api, cand_id: int, visit_label: str, dicom_tar_name: str):
    api.call('v0.0.4-dev', f'/candidates/{cand_id}/{visit_label}/dicoms/{dicom_tar_name}')
    # TODO: Handle returned file
