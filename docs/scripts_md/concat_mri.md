# NAME
concat\_mri.pl - aggregates MINC files that have a common set of properties.

# SYNOPSIS
concat\_mri.pl \[options\] \[minc\_files\]

- **-clean** : remove the original files when they are concatenated
- **-clobber** : overwrite existing output file(s)
- **-debug** : print commands but do not execute them
- **-verbose** : print additional information while running
- **-compress** : compress resulting output files with `gzip`
- **-stdin** : do not read the names of the MINC files on the command line but read them
from `STDIN` instead
- **-postfix text** : create output file names using the file name without its extension, followed
by `text` and the extension. For example, if `-postfix _test` is used and the file name
passed on the command line is `scan.mnc`, the resulting output file will be `scan_test.mnc`.
If there is not `-postfix` option on the command line, output files will be created as if 
`-postfix _concat` had been used.
- **-target\_dir dir** : use `dir` as the directory where output files will be written. By 
default the output files are written in the current directory.
- **-ignorecontrast** : ignore the contrast agent flag in the file headers
- **-minslicesep sep** : do not concatenate the files if the resulting slice separation 
is less than `sep`. If this option is not used, `-minslicesep 1` is assumed.
- **-maxslicesep sep** : do not concatenate if the resulting slice separation is more 
than `sep`. If this option is not used, `-maxslicesep 3` is assumed.
- **-nonslicetolerance tolerance** : resample input volumes when the difference in 
start values in one of the non-slice dimensions exceeds `tolerance`. If this option
is not used `-nonslicetolerance 1e-5` is assumed.
- **-slicetolerance tolerance** : allow `tolerance` when judging concatenate ability 
based on the start values in the slice dimension. If this option is not used, 
`-slicetolerance 0.05` is assumed.
- **-step step** : step used in final resampling. By default, the step size is computed
automatically.

# DESCRIPTION

This script parses the MINC files passed on the command line (or read from `STDIN`) and
uses `mincinfo` to extract specific header information from each of them. It then groups
together the files that have identical values for the following properties: 
patient name, study ID, contrast agent flag (unless `-ignorecontrast` is specified, see 
above), list of dimension names, step values (slice separation) for each of the dimension
and start values for all dimensions (except the first one in the list of dimension names). 
Once the groups are created, the script proceeds to aggregate those files that belong to 
a given group and for which stacking or interleaving occurs in the slice direction (this 
will be the first element in the list of dimension names). Note that `mincresample` might 
be called on a specific file before the actual merging takes place (see `-nonslicetolerance`
above). Finally, note that merging of the MINC files is done with `mincconcat`. 

# LICENSING

License: GPLv3

# AUTHORS

Alex P. Zijdenbos,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
