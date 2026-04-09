# LORIS electrophysiology chunker

## Description

A set of scripts to chunk EEG and MEG data in smaller bits for visualization in the LORIS electrophysiology browser.

## Installation

The LORIS electrophysiology chunker can be installed as a Python package by using the following command from the root LORIS Python directory:

```sh
pip install python/loris_ephys_chunker
```

## Scripts

The LORIS electrophysiology chunker currently supports the following file types with the following scripts:
- EEG EDF: `edf-to-chunks`
- EEG EEGLAB: `eeglab-to-chunks`
- MEG CTF: `ctf-to-chunks`

## Use

The LORIS electrophysiology chunker can be used using the following command:

```sh
script path/to/acquisition -d path/to/destination/dir
```

## Credits

These scripts were extracted on July 8th, 2019 from the master branch of the following Github repository:
https://github.com/ArminTaheri/react-series-data-viewer.

Author: Armin Taheri; armin.taheri@mcgill.ca
