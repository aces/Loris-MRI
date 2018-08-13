# NAME

NeuroDB::ExitCodes -- Class regrouping all the exit codes used by the imaging
insertion scripts

# SYNOPSIS

    use NeuroDB::ExitCodes;

    # testing if an argument was given to the script
    if ( !$ARGV[0] ) {
        print $Help;
        print "$Usage\n\tERROR: Missing argument\n\n";
        exit $NeuroDB::ExitCodes::MISSING_ARG;
    }

    # if script ran successfuly, exit with success exit code (a.k.a. 0)
    exit $NeuroDB::ExitCodes::SUCCESS;

# DESCRIPTION

This class lists all the exit codes used by the imaging insertion scripts.

The exit codes are organized per script, together with a section that
represents common failures to most scripts. For each script, exit codes are
organized based on their use (validation failures, database related failures,
file related failures, script execution failures, study related failures,
input error checking and setting failures). Note that not all of the possible
exit codes are used by each script, giving some room to add some later on if
needed.

Below is a list of the possible exit codes:

\##### ---- SECTION 1:  EXIT CODES COMMON TO MOST IMAGING INSERTION SCRIPTS

1\. Success: exit code = 0 upon success.

2\. Common input error checking and setting failures (exit codes from 1 to 19)

3\. Common database related failures (exit codes from 20 to 39)

4\. Common configuration failures (exit codes from 40 to 59)

5\. Common file manipulation failures (exit codes from 60 to 79)

6\. Other common generic failures (exit codes from 80 to 149)

\##### ---- SECTION 2: SCRIPT SPECIFIC EXIT CODES NOT COVERED IN SECTION 1

7\. Exit codes from `batch_uploads_imageuploader` (exit codes from 150 to 159)

8\. Exit codes from `DTIPrep/DTIPrepRegister.pl` (exit codes from 160 to 169)

9\. Exit codes from `uploadNeuroDB/NeuroDB/ImagingUpload.pm` (exit codes from
170 to 179)

10\. Exit codes from `uploadNeuroDB/minc_insertion.pl` (exit codes from 180
to 189)

11\. Exit codes from `uploadNeuroDB/tarchiveLoader` (exit codes from 190 to 199)

12\. Exit codes from former scripts that have been removed (exit codes from 200
to 210)

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience
