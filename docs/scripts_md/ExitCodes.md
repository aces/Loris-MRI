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

Below is a list of the possible exit codes organized per script:

1\. Common exit codes to most insertion scripts (exit codes from 0 to 19, 0 =
exit script with success status)

2\. Exit codes from batch\_uploads\_imageuploader (exit codes from 20 to 49)

3\. Exit codes from batch\_uploads\_tarchive (no exit codes available yet, exit
codes will be from 60 to 69)

4\. Exit codes from dicom-archive/dicomTar.pl (exit codes from 80 to 89)

5\. Exit codes from dicom-archive/updateMRI\_upload (exit codes from 100 to 119)

6\. Exit codes from DTIPrep/DTIPrep\_pipeline.pl (exit codes from 120 to 139)

7\. Exit codes from DTIPrep/DTIPrepRegister.pl (exit codes from 140 to 159)

8\. Exit codes from uploadNeuroDB/imaging\_upload\_file.pl (exit codes from 160
to 179)

9\. Exit codes from uploadNeuroDB/NeuroDB/ImagingUpload.pm (exit codes from 180
to 199)

10\. Exit codes from uploadNeuroDB/NeuroDB/MRIProcessingUtility.pm (exit codes
 from 200 to 219)

11\. Exit codes from uploadNeuroDB/minc\_deletion.pl (exit codes from 220 to 239)

12\. Exit codes from uploadNeuroDB/minc\_insertion.pl (exit codes from 230 to 259)

13\. Exit codes from uploadNeuroDB/register\_processed\_data.pl (exit codes from
260 to 279)

14\. Exit codes from uploadNeuroDB/tarchiveLoader (exit codes from 280 to 299)

# LICENSING

License: GPLv3

# AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience
