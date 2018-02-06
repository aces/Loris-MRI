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

The exit codes are organized per script, allowing 10 exit codes per script
(note, not all of the possible exit codes are used by each script, giving
some room to add some later on if needed). For each scripts, exit codes are
organized based on their use (validation failures, database related failures,
file related failures, script execution failures, study related failures,
input error checking and setting failures).

Below is a list of the possible exit codes organized per script:

1\. Common exit codes to most insertion scripts (exit codes from 0 to 9, 0 =
exit script with success status)

2\. Exit codes from batch\_uploads\_imageuploader (exit codes from 10 to 19)

3\. Exit codes from batch\_uploads\_tarchive (no exit codes available yet, exit
codes will be from 20 to 29)

4\. Exit codes from dicom-archive/dicomTar.pl (exit codes from 30 to 39)

5\. Exit codes from dicom-archive/updateMRI\_upload (exit codes from 40 to 49)

6\. Exit codes from DTIPrep/DTIPrep\_pipeline.pl (exit codes from 50 to 59)

7\. Exit codes from DTIPrep/DTIPrepRegister.pl (exit codes from 60 to 69)

8\. Exit codes from uploadNeuroDB/imaging\_upload\_file.pl (exit codes from 70
to 79)

9\. Exit codes from uploadNeuroDB/NeuroDB/ImagingUpload.pm (exit codes from 80
to 89)

10\. Exit codes from uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm (exit codes
 from 90 to 99)

11\. Exit codes from uploadNeuroDB/minc\_deletion.pl (exit codes from 100 to 109)

12\. Exit codes from uploadNeuroDB/minc\_insertion.pl (exit codes from 110 to 119)

13\. Exit codes from uploadNeuroDB/register\_processed\_data.pl (exit codes from
120 to 129)

14\. Exit codes from uploadNeuroDB/tarchiveLoader (exit codes from 130 to 139)

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience
