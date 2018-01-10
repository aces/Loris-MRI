# NAME

seriesuid2fileid -- a script that displays relevant information and tracks the
status of an acquired imaging series based on the series UID as an input
argument (provided as a STDIN).

# SYNOPSIS

perl tools/seriesuid2fileid

There are no available options. Once the script is invoked, series UID can be
input to display the status. The $profile file for database connection
credentials is assumed to be \`prod\`.

# DESCRIPTION

The program takes series UID from STDIN and returns a report with:

    - SeriesUID
    - SeriesDescription
    - TarchiveID
    - m_p_v_s_ID
    - mri_v_log
    - FileID
    - FileName

# TO DO

Nothing planned.

# BUGS

None reported.

# LICENSING

License: GPLv3

# AUTHORS

Gregory Luneau, LORIS community <loris.info@mcin.ca> and McGill Centre for
Integrative Neuroscience
