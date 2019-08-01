#!/usr/bin/perl 
# Jonathan Harlap 2006
# jharlap@bic.mni.mcgill.ca
# Perl tool to update headers in a dicomTar archive.
# $Id: updateHeaders.pl 4 2007-12-11 20:21:51Z jharlap $

=pod

=head1 NAME

updateHeaders.pl -- updates DICOM headers for an entire study or a specific series
in a DICOM archive


=head1 SYNOPSIS

perl tools/updateHeaders.pl C<[options]> C<[/path/to/DICOM/or/TARCHIVE]>

Available options are:

-series  : applies the update only to the series with the specified series number

-set     : set a header field to a value (-set <field name> <value>). Field name
		   should be specified either as '(xxxx,yyyy)' or using names recognized
		   by dcmtk. May be called more than once.

-database: Enable C<dicomTar>'s database features

-profile : Name of the config file in C<../dicom-archive/.loris_mri>

-verbose : Be verbose

-version : Print version and revision number and exit

=head1 DESCRIPTION

A script that updates DICOM headers for an entire study or a specific series
in a DICOM archive. If run with the C<-database> option, it will update the
C<tarchive> tables with the updated DICOM archive.

=head1 METHODS

=cut

use strict;

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname basename /;
use File::Find;
use File::Temp qw/ tempdir /;
use Getopt::Tabular;

use DICOM::DICOM;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $verbose = 0;
my $database = 0;
my $profile    = undef;
my @setList = ();
my @leftovers = ();
my $targetSeriesNumber = undef;

my $Usage = "------------------------------------------

$0 updates DICOM headers for an entire study or a specific series in a dicomTar archive.

Usage:\n\t $0 </PATH/TO/ARCHIVE> [-set <DICOM field name> <new value>] \\
\t\t[-set <DICOM field name> <new value>] ... [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
	 (
	  ["Main options", "section"],
	  ["-series", "integer", 1, \$targetSeriesNumber, "Applies the update only to the series with the specified series number."],
	  ["-set", "call", undef, \&handle_set_options, "Set a header field to a value (-set <field name> <value>).  Field name should be specified either as '(xxxx,yyyy)' or using names recognized by dcmtk.  May be called more than once."],

	  ["General options", "section"],
	  ["-database", "boolean", 1, \$database, "Enable dicomTar's database features"],
	  ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory."],
	 
	  ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
	  ["-version", "call", undef, \&handle_version_option, "Print version and revision number and exit"],
		);


# Parse arguments
&GetOptions(\@arg_table, \@ARGV, \@leftovers)
	|| exit $NeuroDB::ExitCodes::GETOPT_FAILURE;

unless(scalar(@leftovers) == 1) {
	 print $Usage;
	 exit($NeuroDB::ExitCodes::GETOPT_FAILURE);
}

################################################################
################### input option error checking ################
################################################################
if ( !$profile ) {
	print $Usage;
	print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
	exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
	print STDERR "\n\tERROR: You don't have a \@db setting in the file "
		. "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
	exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

# connect to the database
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

# grep config info
my $bin_dirPath        = &NeuroDB::DBI::getConfigSetting(\$dbh,'MRICodePath'       );
my $tarchiveLibraryDir = &NeuroDB::DBI::getConfigSetting(\$dbh,'tarchiveLibraryDir');
$tarchiveLibraryDir    =~ s/\/$//g;
$bin_dirPath           =~ s/\/$//;

my $tarchive = $leftovers[0];
unless($tarchive =~ /^\//) {
  $tarchive = "$tarchiveLibraryDir/$tarchive";
}
print "Operating on tarchive $tarchive\n" if $verbose;

# create the temp dir
my $tempdir = tempdir( CLEANUP => 1 );

# extract the tarchive
my $dcmdir = &extract_tarchive($tarchive, $tempdir);

# get a list of files to modify
my @filesToUpdate = ();

my $find_handler = sub {
	 my $file = $File::Find::name;
	 if(-f $file) {

		  # read the file, assuming it is dicom
		  my $dicom = DICOM->new();
		  $dicom->fill($file);
		  my $fileIsDicom = 1;
		  my $studyUID = $dicom->value('0020','000D');
		  
		  # see if the file was really dicom
		  if($studyUID eq "") {
				$fileIsDicom = 0;
		  }
		  
		  if($fileIsDicom) {
				if(defined($targetSeriesNumber)) {
					 my $series = trimwhitespace($dicom->value('0020','0011')) + 0;
					 if($series == $targetSeriesNumber) {
						  push @filesToUpdate, $file;
					 }
				} else {
					 push @filesToUpdate, $file;
				}
		  }
	 }
};

find($find_handler, "$tempdir/$dcmdir");

if(scalar(@filesToUpdate) == 0) {
	 print "Error: No files to be modified.  Aborting.\n";
	 exit($NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE);
}

# update the files
foreach my $file (@filesToUpdate) {
	 print "Updating headers for file '$file'\n" if $verbose;
	 &update_file_headers($file, \@setList);
}

# rebuild the tarchive
print "Rebuilding tarchive\n" if $verbose;
my $targetdir = dirname($tarchive);
my $DICOMTAR  = $bin_dirPath . "/dicom-archive/dicomTar.pl";
my $cmd = "$DICOMTAR $tempdir/$dcmdir $targetdir -clobber ";
if($database) {
	 $cmd .= " -database";
}
if(defined($profile)) {
	$cmd .= " -profile $profile";
}

print "Executing $cmd\n" if $verbose;
`$cmd`;
my $exitCode = $?>> 8;
if($exitCode != 0) {
	 print "Error occurred during dicomTar!  Exit code was $exitCode\n" if $verbose;
	 exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
}

exit $NeuroDB::ExitCodes::SUCCESS;

=pod

=head3 extract_tarchive($tarchive, $tempdir)

Extracts the DICOM archive passed as argument in a temporary directory and
returns the extracted DICOM directory.

INPUTS:
  - $tarchive: the DICOM archive to extract
  - $tempdir : the temporary directory to extract the DICOM archive into

RETURNS: the extracted DICOM directory

=cut

sub extract_tarchive {
	 my ($tarchive, $tempdir) = @_;

	 print "Extracting tarchive\n" if $verbose;
	 `cd $tempdir ; tar -xf $tarchive`;
	 opendir TMPDIR, $tempdir;
	 my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
	 closedir TMPDIR;

	 if(scalar(@tars) != 1) {
		  print "Error: Could not find inner tar in $tarchive!\n";

		  print @tars . "\n";
		  exit(1);
	 }

	 my $dcmtar = $tars[0];
	 my $dcmdir = $dcmtar;
	 $dcmdir =~ s/\.tar\.gz$//;

	 `cd $tempdir ; tar -xzf $dcmtar`;
	 
	 return $dcmdir;
}

=pod

=head3 update_file_headers($file, $setRef)

Updates the headers of a DICOM file given as argument to that function.

INPUTS:
  - $file  : DICOM file in which to update headers information
  - $setRef: set of headers/values to update in the DICOM file

=cut

sub update_file_headers {
	 my ($file, $setRef) = @_;
	 
	 # if there was already a backup file, dcmodify would crush it...
	 my $protectedFile;
	 my $backupFile = "${file}.bak";
	 if(-f $backupFile) {
		  (undef, $protectedFile) = tempfile('tempXXXXX', OPEN => 0);
		  `mv '$backupFile' '$protectedFile'`;
	 }

	 my $cmd = "dcmodify ";
	 foreach my $set (@$setRef) {
		  $cmd .= " --insert '".$set->[0]."=".$set->[1]."' ";
	 }
	 $cmd .= "'${file}' 2>&1";
	 
	 `$cmd`;

	 if(defined($protectedFile)) {
		  `mv '$protectedFile' '$backupFile'`;
	 } else {
		  unlink $backupFile;
	 }
}

=pod

=head3 handle_version_option()

Handles the -version option of the GetOpt table.

=cut

sub handle_version_option {
	 my $versionInfo = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;
	 print "Version $versionInfo\n";
	 exit(0);
}

=pod

=head3 handle_set_options($opt, $args)

Handle the -set option of the GetOpt table. It makes sure that two arguments are
following the -set option and stores the <field name>/<new value> information into a
C<@setList> array.

INPUTS:
  - $opt : the name of the option (a.k.a. -set)
  - $args: array of arguments following the name of the option in the GetOpt table

RETURNS: 0 if did not find two arguments after the C<$opt> option, 1 otherwise

=cut

sub handle_set_options {	 
	 my ($opt, $args) = @_;

	 warn ("$opt option requires two arguments\n"), return 0 unless scalar(@$args) > 1;

	 my $fieldName = shift @$args;
	 my $newValue = shift @$args;

	 push (@setList, [$fieldName, $newValue]);
	 return 1;
}

=pod

=head3 trimwhitespace($string)

Removes leading and trailing spaces in a string.

INPUTS: the string to modify

RETURNS: the string without leading and trailing spaces

=cut

sub trimwhitespace {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}


=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Jonathan Harlap, LORIS community <loris.info@mcin.ca> and McGill Centre for
Integrative Neuroscience

=cut
