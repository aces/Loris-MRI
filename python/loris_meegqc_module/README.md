# LORIS MEEGqc module

## Description

This module provides LORIS support for the [MEEGqc](https://ancplaboldenburg.github.io/megqc_documentation/) EEG/MEG quality control tool.

## Installation

This is an optional module not installed with LORIS by default. It can be installed using the following command from the root LORIS Python directory:

```sh
pip install python/loris_module_meegqc
```

## Features

Here are the features provided by this module:
- Import MEEGqc derivatives from a BIDS dataset.
- Serve MEEGqc endpoints for the LORIS electrophysiology browser.

Here are the features not provided by this module yet:
- Run MEEGqc on imported data.
