# LORIS BIDS importer

## Description

The LORIS BIDS importer is a pipeline that allows to ingest an external BIDS dataset into LORIS, populating both the database and the file system.

The LORIS BIDS importer supports the MRI (NIfTI), EEG/iEEG (EDF/EEGLAB), and MEG (CTF) modalities.

## Installation

This package is installed by default with LORIS Python.

## Script

The LORIS BIDS importer can be run using the following command:

```sh
import-bids-dataset -d /path/to/bids/dataset
```

The directory passed as an argument should be a BIDS compliant dataset (see the [BIDS specification](https://bids-specification.readthedocs.io/en/stable/)).

## Parameters

### Subject and session validation

To be imported into LORIS, a BIDS dataset must adhere to the following rules:
- The subject labels of the BIDS dataset should map to LORIS candidate CandIDs or PSCIDs.
- The session labels of the BIDS dataset should map to LORIS visit labels.

If some (or all) candidates or sessions do not exist yet in LORIS, they can be created automatically from the BIDS dataset information using the following options:
- `--create-candidate`: Create new LORIS candidates, in which case the BIDS subject labels must correspond to new or existing LORIS PSCIDs (CandIDs will be automatically generated).
- `--create-session`: Create new LORIS sessions, in which case the BIDS session labels must correspond to existing LORIS visit labels.

Note that these options may require additional information such as the candidate and session projects, sites, and cohorts from the `participants.tsv`, `sessions.tsv`, or `scans.tsv` BIDS files.

### File copy

By default, the files imported from the source BIDS dataset are copied in a new BIDS dataset in the LORIS data directory. The `--no-copy` option allows to re-use the original BIDS files without copy if the source BIDS dataset is already located in the LORIS data directory.

### Other parameters

To see all the CLI parameters of the LORIS BIDS importer, use `import-bids-dataset --help`.

## Configuration

### MRI

The LORIS BIDS importer assigns LORIS scan types to MRI files using the provided BIDS suffixes. For instance, if a NIfTI file is named `sub-ABC000123_ses-ABC_T1map.nii.gz`, it will be assigned the LORIS `T1map` scan type.

The LORIS BIDS importer automatically creates standard BIDS scan types if they do not exist in the LORIS database yet. If a project uses custom BIDS scan types, these should be added in the `mri_scan_type` table beforehand.

### EEG/iEEG/MEG

To be visualized in the LORIS electrophysiology browser, EEG/iEEG/MEG files must be pre-processed by the [LORIS electrophysiology chunker](../loris_ephys_chunker). To enable pre-processing of electrophysiology files during BIDS import, the LORIS `useEEGBrowserVisualizationComponents` configuration value must be set to `true`.

## Supported files

The LORIS BIDS importer can import the following BIDS files:
- Static dataset files: `dataset_description.json`, `README`.
- Dataset structure files: `participants.tsv`, `scans.tsv`.
- MRI acquisition files: NIfTI (`.nii`, `.nii.gz`) and their JSON sidecars.
- EEG/iEEG/MEG acquisition files: EDF (`.edf`), EEGLAB (`.set`), CTF (`.ds` directories), and their JSON sidecars.
- EEG/iEEG/MEG metadata files: `coordsystem.json`, `electrodes.tsv`, `channels.tsv`, `events.json`, `events.tsv`.
