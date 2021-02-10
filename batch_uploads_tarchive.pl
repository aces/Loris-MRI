#!/usr/bin/perl -w

=pod

=head1 NAME

batch_uploads_tarchive - upload a batch of DICOM archives using script
C<tarchiveLoader.pl>

=head1 SYNOPSIS

./batch_uploads_tarchive

=head1 DESCRIPTION

This script uploads a list of DICOM archives to the database by calling script
C<tarchiveLoader.pl> on each file in succession. The list of files to process is read 
from C<STDIN>, one file name per line. Each file name is assumed to be a path
relative to C<tarchiveLibraryDir> (see below).

The following settings of file F<$ENV{LORIS_CONFIG}/.loris-mri/prod> affect the 
behvaviour of C<batch_uploads_tarchive> (where C<$ENV{LORIS_CONFIG}> is the
value of the Unix environment variable C<LORIS_CONFIG>):

=over 4

=item *
B<dataDirBasepath> : controls where the C<STDOUT> and C<STDERR> of each qsub
command (see below) will go, namely in
  F<< $dataDirBasepath/batch_output/tarstdout.log<index> >> and
  F<< $dataDirBasepath/batch_output/tarstderr.log<index> >>
  (where C<< <index> >> is the index of the DICOM archive processed, the
  first file having index 1).
   
=item * 
B<tarchiveLibraryDir>: directory that contains the DICOM archives to process.
The path of the files listed on C<STDIN> should be relative to this directory.
  
=item *
B<is_qsub>: whether the output (STDOUT) of each C<tarchiveLoader.pl> command
should be processed by the C<qsub> Unix command (allows batch execution of jobs
on the Sun Grid Engine, if available). If set, then the C<qsub> command will
send its C<STDOUT> and C<STDERR> according to the value of C<dataDirBasepath>
(see above).
  
=item *
B<mail_use>: upon completion of the script, an email will be sent to email address
  $mail_user containing the list of files processed by C<batch_uploads_tarchive>
  
=back

File prod should also contain the information needed to connect to the database in an
array C<@db> containing four elements:

=over 4

=item *
The database name

=item *
The SQL user name used to connect ot the database

=item *
The password for the user identified above

=item *
The database hostname

=back

=head1 TO DO

Code cleanup: remove unused C<-D> and C<-v> program arguments

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

use strict;
use warnings;
no warnings 'once';
use Getopt::Tabular;

use NeuroDB::DBI;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;


my $profile = undef;
my $verbose = 0;
my $profile_desc = "name of the config file in ../dicom-archive/.loris_mri";

my @opt_table = (
  [ "Basic options", "section" ],
    [ "-profile", "string",  1, \$profile, $profile_desc],
    [ "-verbose", "boolean", 1, \$verbose, "Be verbose."]
);

my $Help = <<HELP;

******************************************************************************
Run tarchiveLoader.pl in batch mode
******************************************************************************

This script runs tarchiveLoader.pl insertion on multiple DICOM archives. The list
of DICOM archives are provided through a text file (e.g. tarchive_list.txt)
with one DICOM archive per line. DICOM archives are specified as the relative
path to the DICOM archive from the tarchive directory
(/data/project/data/tarchive).

An example of what tarchive_list.txt might contain for 3 DICOM archives to be
inserted:
DCM_2015-09-10_MTL0709_475639_V1.tar
DCM_2015-09-10_MTL0709_475639_V2.tar
DCM_2015-09-10_MTL0709_475639_V3.tar

HELP

my $Usage = <<USAGE;

usage: ./batch_uploads_tarchive -profile prod < tarchive_list.txt
       $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV ) || exit 1;


#####Get config setting#######################################################
# checking for profile settings
if (!$profile ) {
    print "You need to specify a profile file using the option '-profile'\n";
    print $Help;
    print "\n$Usage\n";
    exit 3;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named ".
        "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2;
}


# --------------------------------------------------------------
## Establish database connection
# --------------------------------------------------------------

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

print "\nSuccessfully connected to database \n";



# ----------------------------------------------------------------
## Get config setting using ConfigOB
# ----------------------------------------------------------------

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir           = $configOB->getDataDirPath();
my $tarchiveLibraryDir = $configOB->getTarchiveLibraryDir();
my $mail_user          = $configOB->getMailUser();
my $is_qsub            = $configOB->getIsQsub();



# define project space
my ($debug) = (0);

my ($stdoutbase, $stderrbase) = ("$data_dir/batch_output/tarstdout.log", "$data_dir/batch_output/tarstderr.log");
my $stdout = '';
my $stderr = '';
while($_ = $ARGV[0], /^-/) {
    shift;
    last if /^--$/; ## -- ends argument processing
    if (/^-D/) { $debug++ } ## debug level
    if (/^-v/) { $verbose++ } ## verbosity
}

## read input from STDIN, store into array @inputs (`find ....... | this_script`)
my @inputs = ();
my @submitted = ();
while(<STDIN>)
{
    chomp;
    push @inputs, $_;
}
close STDIN;

my $counter = 0;

## foreach series, batch magic
foreach my $input (@inputs)
{
    chomp($input);
    my @linearray = split(' ', $input);
    my $tarchive  = $linearray[0];
    $tarchive     =~ s/\t/ /;
    $tarchive     =~ s/$tarchiveLibraryDir//;
    my $upload_id = $linearray[1];

    if (!$tarchive || !$upload_id) {
        print STDERR "\nERROR: need to provide the ArchiveLocation and its "
                     . "associated UploadID separated by a space.\n\n";
        exit $NeuroDB::ExitCodes::MISSING_ARG;
    }

    $counter++;
    $stdout = $stdoutbase.$counter;
    $stderr = $stderrbase.$counter;

    ## this is where the subprocesses are created...
    ## should basically run processor script with study directory as argument.
    ## processor will do all the real magic

    my $tarchive_path = "$tarchiveLibraryDir/$tarchive";
    my $command = sprintf(
        "tarchiveLoader.pl -profile %s -uploadID %s %s",
        $profile,
        quotemeta($upload_id),
        quotemeta($tarchive_path)
    );
    ##if qsub is enabled use it
    if ($is_qsub) {
	     open QSUB, "| qsub -V -e $stderr -o $stdout -N process_tarchive_${counter}";
    	 print QSUB $command;
    	 close QSUB;
    }
    ##if qsub is not enabled
    else {
         system($command);
    }

     push @submitted, $input;
}
open MAIL, "|mail $mail_user";
print MAIL "Subject: BATCH_UPLOADS_TARCHIVE: ".scalar(@submitted)." studies submitted.\n";
print MAIL join("\n", @submitted)."\n";
close MAIL;

## exit $NeuroDB::ExitCodes::SUCCESS for find to consider this -cmd true (in case we ever run it that way...)
exit $NeuroDB::ExitCodes::SUCCESS;
