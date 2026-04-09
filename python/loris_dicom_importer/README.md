# LORIS DICOM importer

## Description

The LORIS DICOM importer is a pipeline used to import a DICOM study into LORIS.

## Installation

The LORIS DICOM importer can be installer as a Python package by using the following command from the root LORIS Python directory:

```sh
pip install python/loris_dicom_importer
```

## Scripts

The LORIS DICOM importer provides the following commands:
- `import-dicom-study --insert --session --source /path/to/dicom/study/dir`: Import a DICOM study into LORIS.
- `summarize-dicom-study /path/to/dicom/study/dir`: Print the information found in a DICOM study into the console (this is the `DICOM_STUDY_NAME.meta` file inside a DICOM archive).
