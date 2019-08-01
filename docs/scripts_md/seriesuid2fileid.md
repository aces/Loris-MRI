# NAME

seriesuid2fileid -- a script that displays a report about the pipeline insertion
progress and outcome (including MRI violation status) of imaging datasets, based
on series `UID(s)` provided as `STDIN`.

# SYNOPSIS

perl tools/seriesuid2fileid

There are no available options. Once the script is invoked, series `UID` can be
input to display the status. The `$profile` file for database connection
credentials is assumed to be `prod`.

# DESCRIPTION

The program takes series `UID` from `STDIN` and returns a report with:

    - C<SeriesUID>
    - C<SeriesDescription>
    - C<TarchiveID>
    - C<m_p_v_s_ID>
    - C<mri_v_log>
    - C<FileID>
    - C<FileName>

The `m_p_v_s_ID` column displays, if present, the `ID` record from the
`mri_protocol_violated_scans` table together with a count representing the
number of times this scan violated the study MRI protocol, and the `mri_v_log`
displays the `Severity` level of the violations as defined in the
`mri_protocol_checks` table.

# LICENSING

License: GPLv3

# AUTHORS

Gregory Luneau,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
