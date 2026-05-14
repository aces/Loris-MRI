# LORIS BIDS importer

## Description

The LORIS BIDS importer is a pipeline that allows to ingest an external BIDS dataset into LORIS, populating both the database and the file-system.

The LORIS BIDS importer supports the MRI (NIfTI), EEG/iEEG (EDF/EEGLAB), and MEG (CTF) modalities.

## Installation

This package is installed by default with LORIS Python.

## Script

The LORIS BIDS importer can be ran with the following command:

```sh
import-bids-dataset -d /path/to/bids/dataset`
```

The directory passed as an argument should be a BIDS compliant dataset (see the [BIDS specification](https://bids-specification.readthedocs.io/en/stable/)).

## Parameters

### Subject and session validation

To be imported into LORIS, a BIDS dataset must adhere to the following rules:
- The subject labels of the BIDS dataset should map to LORIS candidate CandIDs or PSCIDs.
- The session labels of the BIDS dataset should map to LORIS visit labels.

If the candidates or sessions do not exist yet in LORIS, they can be created automatically from the BIDS dataset information using the following options:
- `--create-candidate`: Create new LORIS candidates, in which case the subject label must be a PSCID (and not a CandID).
- `--create-session`: Create new LORIS sessions.

Note that these options may require additional information such as the candidate and session projects, sites, and cohorts from the `participants.tsv`, `sessions.tsv`, or `scans.tsv` BIDS files.

### File copy

By default, the files imported from the source BIDS dataset are copied in a new BIDS dataset in the LORIS data directory. The `--no-copy` option allows to re-use the original BIDS files without copy if the source BIDS dataset is already located in the LORIS data directory.

### Other parameters

To see all the CLI parameters of the LORIS BIDS importer, use `import-bids-dataset --help`.

## Supported files

The LORIS BIDS importer can import the following BIDS files:
- Static dataset files: `dataset_description.json`, `README`.
- Dataset structure files: `participants.tsv`, `scans.tsv`.
- MRI acquisition files: NIfTI (`.nii`, `.nii.gz`) and their JSON sidecars.
- EEG/iEEG/MEG acquisition files: EDF (`.edf`), EEGLAB (`.set`), CTF (`.ds` directories), and their JSON sidecars.
- EEG/iEEG/MEG metadata files: `coordsystem.json`, `electrodes.tsv`, `channels.tsv`, `events.json`, `events.tsv`.
