#!/usr/bin/perl -w

=pod

=head1 NAME

batch_uploads_tarchive - upload a batch of DICOM archives using script
C<tarchiveLoader>

=head1 SYNOPSIS

./batch_uploads_tarchive

=head1 DESCRIPTION

This script uploads a list of DICOM archives to the database by calling script
C<tarchiveLoader> on each file in succession. The list of files to process is read 
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
B<is_qsub>: whether the output (STDOUT) of each C<tarchiveLoader> command
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
use NeuroDB::DBI;
use NeuroDB::ExitCodes;


#####Get config setting#######################################################
# checking for profile settings
if(-f "$ENV{LORIS_CONFIG}/.loris_mri/prod") {
    { package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }
} ##Possibly the script can exit if the prod doesn't exist
#######################################################################################

################################################################
######### Establish database connection ########################
################################################################
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\nSuccessfully connected to database \n";

# define project space
my ($debug, $verbose) = (0,0);
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'tarchiveLibraryDir'
                    );
my $is_qsub = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'is_qsub'
                    );
my $mail_user = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'mail_user'
                    );

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
    $counter++;
    $stdout = $stdoutbase.$counter;
    $stderr = $stderrbase.$counter;

    #$stdout = '/dev/null';
    #$stderr = '/dev/null';

    ## this is where the subprocesses are created...  should basically run processor script with study directory as argument.
    ## processor will do all the real magic

    $input =~ s/\t/ /;
    $input =~ s/$tarchiveLibraryDir//;
    my $command = "tarchiveLoader.pl -globLocation -profile prod $tarchiveLibraryDir/$input";
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
