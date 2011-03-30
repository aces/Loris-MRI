#!/usr/bin/perl 
# Perl tool to update headers for data coming from LDZ so the EN is present and the converter we are using won't fail 
# $Id: LDZfix.pl 3 2007-12-11 20:10:36Z jharlap $

use strict;
use Cwd qw/ abs_path /;
use File::Basename qw/ basename dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use FindBin;
use Getopt::Tabular;

use lib "$FindBin::Bin";
use DICOM::DICOM;

$|++;

my $verbose = 1;
my @leftovers = ();
my $ldzf = undef;
my $profile = 'transfer';
my $dryrun = 0; 
my $archive = "/export-01/innomed/mri-data/archive";

my $Usage = "------------------------------------------

This will do 4 things

1. Figure out the series number of t2/pd contained within the folder 
2. Write a study specific spec file to modify echo number using updateHeadersBatch.pl and put it within the folder
3. Create a tarchive containing all the data
4. Run updateHeadersBatch.pl which will update the series and recreate the archive.

$0 updates DICOM headers for data from LDZ

Usage:\n\t $0 </PATH/TO/DCMFolder> 
\n\n See $0 -help for more info\n\n";

my @arg_table =
    (
     ["The only option", "section"],
     ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .neurodb in your home directory."],
     ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
     ["-dryrun", "boolean", 1, \$dryrun, "Don't do anything just tell me what would happen."],
     );

&GetOptions(\@arg_table, \@ARGV, \@leftovers) || exit 1;

unless(scalar(@leftovers) == 1 && $profile) {
	 print $Usage;
	 exit(1);
}
my $ldzf = abs_path($leftovers[0]);
if (-d $ldzf && $ldzf =~ /LDZ/) { print "\nSelected study folder:\t $ldzf\n" }
else { print "\n\tERROR: The target is not a directory or does not contain LDZ data!\n"; exit 33; }

# 1.
{ package Settings; do "$ENV{HOME}/.neurodb/$profile" || exit}
my $get_dicom_info   = $Settings::get_dicom_info;
my $series = `find $ldzf -type f | $get_dicom_info -stdin -series -te -echo -slice_thickness | sort -u | grep 80 | cut -f 1\n`;
# fixme this is really dirty
my @series = split(" \n", $series);
foreach my $s (@series) {  print "PD/T2 series SN:\t $s\n"; }

# 2.
my $specfile = "$ldzf/specfile";
# if (-e $specfile) { print "ERROR: spec exists so something is wrong.\n"; exit; } 
open SPEC, ">$specfile";
SPEC->autoflush(1);
select(SPEC);
# put the right content:
foreach my $s (@series) {
    print "(0020,0011)\t${s}\t(0018,0081)\t16\t(0018,0086)\t0\t(0008,103e)\tPD EN adjusted\n";
    print "(0020,0011)\t${s}\t(0018,0081)\t80\t(0018,0086)\t1\t(0008,103e)\tT2 EN adjusted\n";
}
close SPEC;
select(STDOUT);
print "\nThis is the specfile that has been created for you:\n\n";
my $mods = `cat $specfile`;
print $mods;

# 3.
print "\nINFO: Creating temporary tarchive.\n\n";
my $DICOMTAR = $FindBin::Bin . "/dicomTar.pl";
my $cmd = "$DICOMTAR $ldzf $archive -profile $profile -database -center LDZ";
my $exitcode = system($cmd); 
# Make sure the thing stops if the tarball already exists.
if ($exitcode > 0) { 
    print "\nODDITY:\tTarchive already exists. This might not be new data. Stopping now.\n\n";
    exit;
}

# 4.
my $currentID = basename($ldzf);
my $tarball = `find $archive -type f | grep $currentID | grep DCM`;
chomp($tarball);

print "fix PD/T2 series for:\t $currentID\n";
print "Affected tarball:\t $tarball\n";

if (-e $tarball) {
    print "\nINFO: Now I will update T2 and PD series.\n\n";
    my $UPDATE = $FindBin::Bin . "/updateHeadersBatch.pl $tarball -spec $specfile -keys 2 -verbose -database -profile $profile";
    `$UPDATE`;
    print "\nDone! You may now rsync and upload the data.\n";
}

