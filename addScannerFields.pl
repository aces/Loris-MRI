#!/usr/bin/perl 
# Jonathan Harlap 2006
# jharlap@bic.mni.mcgill.ca
# Perl tool to update the tarchive table, filling in the scanner fields
# $Id: addScannerFields.pl 4 2007-12-11 20:21:51Z jharlap $

use strict;

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use FindBin;
use Getopt::Tabular;

use lib "$FindBin::Bin";
use DICOM::DICOM;
use DB::DBI;

my $verbose = 0;
my $profile    = undef;
my @setList = ();
my @leftovers = ();
my $targetSeriesNumber = undef;

my $Usage = "------------------------------------------

$0 updates a database to fill the scanner fields.

Usage:\n\t $0 -profile <profile>
\n\n See $0 -help for more info\n\n";

my @arg_table =
	 (
	  ["Main options", "section"],
	  ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory."],
	 
	  ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
	  ["-version", "call", undef, \&handle_version_option, "Print version and revision number and exit"],
		);


# Parse arguments
&GetOptions(\@arg_table, \@ARGV, \@leftovers) || exit 1;

unless(scalar(@leftovers) == 0) {
	 print $Usage;
	 exit(1);
}

# checking for profile settings
if(-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; exit 33;
} 
if(!$profile) { print $Usage; print "\n\tERROR: You must specify an existing profile.\n\n";  exit 33;  }

# establish database connection if database option is set
my $dbh = &DB::DBI::connect_to_db(@Settings::db); print "Connecting to database.\n" if $verbose;

# get $tarchiveLibraryDir from profile
my $tarchiveLibraryDir = $Settings::tarchiveLibraryDir;
$tarchiveLibraryDir    =~ s/\/$//g;

my $sth = $dbh->prepare("SELECT DicomArchiveID, ArchiveLocation FROM tarchive WHERE ScannerManufacturer='' AND ScannerModel=''");
$sth->execute();
if($sth->rows < 1) {
   print "\n\tERROR: No tarchives found which lack manufacturer or model \n\n"; exit 33;
} 

my $updatesth = $dbh->prepare("UPDATE tarchive SET ScannerManufacturer=?, ScannerModel=?, ScannerSerialNumber=?, ScannerSoftwareVersion=? WHERE DicomArchiveID=?");

 TARCHIVE:
    while(my @row = $sth->fetchrow_array()) {
        my $tarchive = $tarchiveLibraryDir . "/" . $row[1];
        print "Starting to work on $tarchive\n" if $verbose;
        
        # create the temp dir
        my $tempdir = tempdir( CLEANUP => 0 );
        
        # extract the tarchive
        my $dcmdir = &extract_tarchive($tarchive, $tempdir);
        
        # get one dicom file
        my $dicomFile;
        
        my $find_handler = sub {
            return if defined $dicomFile;
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
                    $dicomFile = $dicom;
                    print "Found DICOM file $file\n" if $verbose;
                }
            }
        };
        
        find($find_handler, "$tempdir/$dcmdir");
        
        unless(defined($dicomFile)) {
            print "Error: Found no dicom files in $tarchive\n";
            next TARCHIVE;
        }
        
        
        $updatesth->execute($dicomFile->value('0008','0070'),
                            $dicomFile->value('0008','1090'),
                            $dicomFile->value('0018','1000'),
                            $dicomFile->value('0018','1020'),
                            $row[0]);

        print "Updated $tarchive with values ".$dbh->quote($dicomFile->value('0008','0070'))." "
            .$dbh->quote($dicomFile->value('0008','1090'))." "
            .$dbh->quote($dicomFile->value('0018','1000'))." "
            .$dbh->quote($dicomFile->value('0018','1020'))."\n" if $verbose;

        `rm -fr $tempdir`;
    }

print "Done!\n";
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
