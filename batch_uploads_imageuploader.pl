#!/usr/bin/perl -w

=pod

=head1 NAME

batch_uploads_imageuploader -- a script that runs C<imaging_upload_file.pl> in
batch mode

=head1 SYNOPSIS

./batch_uploads_imageuploader -profile prod < list_of_scans.txt > log_batch_imageuploader.txt 2>&1 C[options]>

Available options are:

-profile: name of the config file in C<../dicom-archive/.loris_mri>

-verbose: if set, be verbose


=head1 DESCRIPTION


This script runs the Loris-MRI insertion pipeline on multiple scans. The list of
scans are provided through a text file (e.g. C<list_of_scans.txt>) with one scan
details per line.
The scan details includes the path to the scan, identification as to whether the
scan is for a phantom (Y) or not (N), and the candidate name for non-phantom
entries.

Like the LORIS Imaging Uploader interface, this script also validates the
candidate's name against the (start of the) filename and creates an entry in the
C<mri_upload> table.

An example of what C<list_of_scans.txt> might contain for 3 uploads to be
inserted:

 /data/incoming/PSC0001_123457_V1.tar.gz N PSC0000_123456_V1
 /data/incoming/lego_Phantom_MNI_20140101.zip Y
 /data/incoming/PSC0001_123457_V1_RES.tar.gz N PSC0000_123456_V1


=head2 Methods

=cut


use strict;
use warnings;
no warnings 'once';
use File::Basename;
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::Notify;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;



my $profile   = '';
my $upload_id = undef; 
my ($debug, $verbose) = (0,1);
my $stdout = '';
my $stderr = '';

my @opt_table           = (
    [ "Basic options", "section" ],
    [
        "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ],
    ["-verbose", "boolean", 1,   \$verbose, "Be verbose."]
);

my $Help = <<HELP;
******************************************************************************
Run imaging_upload_file.pl in batch mode
******************************************************************************

This script runs the Loris-MRI insertion pipeline on multiple scans. The list of
scans are provided through a text file (e.g. C<list_of_scans.txt>) with one scan
details per line.
The scan details includes the path to the scan, identification as to whether the
scan is for a phantom (Y) or not (N), and the candidate name for non-phantom
entries.

Like the LORIS Imaging Uploader interface, this script also validates the
candidate's name against the (start of the) filename and creates an entry in the
mri_upload table.

An example of what C<list_of_scans.txt> might contain for 3 uploads to be
inserted:

 /data/incoming/PSC0001_123457_V1.tar.gz N PSC0000_123456_V1
 /data/incoming/Lego_Phantom_MNI_20140101.zip Y
 /data/incoming/PSC0001_123457_V1_RES.tar.gz N PSC0000_123456_V1

Documentation: perldoc batch_uploads_imageuploader

HELP
my $Usage = <<USAGE;
usage: ./batch_uploads_imageuploader.pl -profile prod < list_of_scans.txt > log_batch_imageuploader.txt 2>&1 [options]
       $0 -help to list options
USAGE
&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

################################################################
################ Get config setting#############################
################################################################
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}


# ----------------------------------------------------------------
## Establish database connection
# ----------------------------------------------------------------

# old database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# new Moose database connection
my $db  = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();


# ----------------------------------------------------------------
## Get config setting using ConfigOB
# ----------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir  = $configOB->getDataDirPath();
my $mail_user = $configOB->getMailUser();
my $bin_dir   = $configOB->getMriCodePath();
my $is_qsub   = $configOB->getIsQsub();




my ($stdoutbase, $stderrbase) = ("$data_dir/batch_output/imuploadstdout.log", 
				 "$data_dir/batch_output/imuploadstderr.log");

while($_ = $ARGV[0] // '', /^-/) {
    shift;
    last if /^--$/; ## -- ends argument processing
    if (/^-D/) { $debug++ } ## debug level
    if (/^-v/) { $verbose++ } ## verbosity
}

## read input from STDIN, store into array @inputs (`find ....... | this_script`)
my @patientnamearray = ();
my @fullpatharray = ();
my @phantomarray = ();
my @submitted = ();

my $counter = 0;

while(my $line = <STDIN>)
{
    chomp $line;

    my @linearray = split(" " , $line);
    push (@fullpatharray,    $linearray[0]);
    push (@phantomarray,     $linearray[1]);
    push (@patientnamearray, $linearray[2]);
}
close STDIN;

## foreach series, batch magic
foreach my $input (@fullpatharray)
{
    $counter++;
    $stdout = $stdoutbase.$counter;
    $stderr = $stderrbase.$counter;

    #$stdout = '/dev/null';
    #$stderr = '/dev/null';

    my $fullpath    = $fullpatharray[$counter-1];
    my $phantom     = $phantomarray[$counter-1];
    my $patientname = $patientnamearray[$counter-1];

    ## Ensure that 
    ## 1) the uploaded file is of type .tgz or .tar.gz or .zip
    ## 2) check that input file provides phantom details (Y for phantom, N for real candidates)
    ## 3) for non-phantoms, the patient name and path entries are identical; this mimics the imaging uploader in the front-end
    my ($base,$path,$type) = fileparse($fullpath, qr{\..*});
    if (($type ne '.tgz') && ($type ne '.tar.gz') && ($type ne '.zip')) {
	print STDERR "The file on line $counter is not of type .tgz, tar.gz, or "
                 . ".zip and will not be processed\n";
	exit $NeuroDB::ExitCodes::FILE_TYPE_CHECK_FAILURE;
    }
    if (($phantom eq '') || (($phantom ne 'N') && ($phantom ne 'Y'))) {
	print STDERR "Make sure the Phantom entry is filled out "
	             . "with Y if the scan if for a phantom, and N otherwise\n";
	exit $NeuroDB::ExitCodes::PHANTOM_ENTRY_FAILURE;
    }
    if ($phantom eq 'N') {
        if ($patientname ne (substr ($base, 0, length($patientname)))) {
       	    print STDERR "Make sure the patient name $patientname for "
	                     . "non-phantom entries matches the start of $base "
	                     . "filename in $path\n";
	        exit $NeuroDB::ExitCodes::PNAME_FILENAME_MISMATCH;
	    }
    }
    else {
        if ($patientname ne '') {
       	    print STDERR "Please leave the patient name blank for phantom "
       	                 . "entries\n";
	        exit $NeuroDB::ExitCodes::PNAME_FILENAME_MISMATCH;
	}
	else {
	    $patientname = 'NULL';
	}
    }

    ## Populate the mri_upload table with necessary entries and get an upload_id 

    $upload_id = insertIntoMRIUpload(\$dbh,
				     $patientname,
                                     $phantom,
                                     $fullpath);

    ## this is where the subprocesses are created...  should basically run processor script with study directory as argument.
    ## processor will do all the real magic

    my $command = "$bin_dir/uploadNeuroDB/imaging_upload_file.pl "
		. "-profile $profile -upload_id $upload_id $fullpath";
    if ($verbose) {
        $command .= " -verbose";
    }

    ##if qsub is enabled use it
    if ($is_qsub) {
	     open QSUB, "| qsub -V -e $stderr -o $stdout -N process_imageuploader_${counter}";
    	 print QSUB $command;
    	 close QSUB;
    }
    ##if qsub is not enabled
    else {
	print "Running now the following command: $command\n" if $verbose;
	system($command);
    }

     push @submitted, $input;
}
open MAIL, "|mail $mail_user";
print MAIL "Subject: BATCH_UPLOADS_IMAGEUPLOADER: ".scalar(@submitted)." studies submitted.\n";
print MAIL join("\n", @submitted)."\n";
close MAIL;


################################################################
############### insertIntoMRIUpload ############################
################################################################

=pod
insertIntoMRIUpload()
Description:
  - Insert into the mri_upload table entries for data coming
    from batch_upload_imageuploader.pl

=head3 insertIntoMRIUpload($patientname, $phantom, $fullpath)

Function that inserts into the C<mri_upload> table entries for data coming from
the list of scans in the text file provided when calling
C<batch_upload_imageuploader>

INPUTS:
    - $patientname  : The patient name
    - $phantom      : 'Y' if the entry is for a phantom,
                      'N' otherwise
    - $fullpath     : Path to the uploaded file



RETURNS: $upload_id : The upload ID

=cut



sub insertIntoMRIUpload {

    my ( $dbhr, $patientname, $phantom, $fullpath ) = @_;
    my $User = getpwuid($>);

    my $query = "INSERT INTO mri_upload ".
                "(UploadedBy, UploadDate, PatientName, ".
                "IsPhantom, UploadLocation) ".
                "VALUES (?, now(), ?, ?, ?)";
    my $mri_upload_insert = $dbh->prepare($query);
    $mri_upload_insert->execute($User,$patientname,
                                $phantom, $fullpath);

    my $where = " WHERE mu.UploadLocation =?";
    $query = "SELECT mu.UploadID FROM mri_upload mu";
    $query .= $where;
    my $sth = $dbh->prepare($query);
    $sth->execute($fullpath);
    my $upload_id = $sth->fetchrow_array;

    return $upload_id;
}

## exit $NeuroDB::ExitCodes::SUCCESS for find to consider this -cmd true (in case we ever run it that way...)
exit $NeuroDB::ExitCodes::SUCCESS;

__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut
