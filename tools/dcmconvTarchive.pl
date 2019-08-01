#!/usr/bin/perl 
# Jonathan Harlap 2006
# jharlap@bic.mni.mcgill.ca
# Perl tool to run dcmconv on all the dicom files in a dicomTar archive.
# $Id: dcmconvTarchive.pl 4 2007-12-11 20:21:51Z jharlap $

use strict;

use Cwd qw/ abs_path /;
use File::Basename qw/ basename dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use Getopt::Tabular;

use DICOM::DICOM;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $verbose = 0;
my $database = 0;
my $profile    = undef;
my @leftovers = ();

my $Usage = "------------------------------------------

$0 updates DICOM files with dcmconv for an entire tarchive.

Usage:\n\t $0 </PATH/TO/ARCHIVE> [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
	 (
	  ["General options", "section"],
	  ["-database", "boolean", 1, \$database, "Enable dicomTar's database features"],
	  ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory"],
	 
	  ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
	  ["-version", "call", undef, \&handle_version_option, "Print version and revision number and exit"],
		);


# Parse arguments
&GetOptions(\@arg_table, \@ARGV, \@leftovers) || exit 1;

unless(scalar(@leftovers) == 1) {
	 print $Usage;
	 exit(1);
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
my $dbh         = &NeuroDB::DBI::connect_to_db(@Settings::db);
my $bin_dirPath = NeuroDB::DBI::getConfigSetting(\$dbh,'MRICodePath');
$bin_dirPath    =~ s/\/$//;

my $tarchive = $leftovers[0];
unless($tarchive =~ /^\//) {
  $tarchive = abs_path(dirname($tarchive)) . '/' . basename($tarchive);
}

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
              dcmconv($file);
		  }
	 }
};

find($find_handler, "$tempdir/$dcmdir");

# rebuild the tarchive
print "Rebuilding tarchive\n" if $verbose;
my $targetdir = dirname($tarchive);
my $DICOMTAR  = $bin_dirPath . "/dicom-archive/dicomTar.pl";
my $cmd = "$DICOMTAR $tempdir/$dcmdir $targetdir -clobber";
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
	 exit 1;
}

exit 0;



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

sub dcmconv {
	 my ($file) = @_;
	 
	 my $cmd = "dcmconv '${file}' '${file}'";
	 `$cmd`;
}

sub handle_version_option {
	 my ($opt, $args) = @_;

	 my $versionInfo = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;
	 print "Version $versionInfo\n";
	 exit(0);
}

sub trimwhitespace {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
