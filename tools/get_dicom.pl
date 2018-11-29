#!/usr/bin/perl -w 
use strict;

=pod

=head1 NAME

get_dicom.pl - extracts DICOM files for specific patient names/scan types

=head1 SYNOPSIS

perl get_dicom.pl [-p profile] [-n patient_name_patterns] [-t scan_type_patterns] [-d tmp_dir] [-o tarBasename]

Available options are:

-p      : name of the config file in C<../dicom-archive/.loris_mri> (defaults to
          prod).
-n      : comma separated list of MySQL patterns for the patient names that a DICOM file
          has to have in order to be extracted. A DICOM file only has to match one of the 
          patterns to be extracted. If no pattern is specified, then the patient name is 
          not used to determine which DICOM files to extract.
-t      : comma separated list of MySQL patterns of the acquisition protocols (scan types
          names) that a DICOM file has to have in order to be extracted. A DICOM file only
          has to match one of the patterns to be extracted. If no pattern is specified, then
          the scan type name is not used to determine which DICOM files to extract.
-d      : extract the files in directory <dir_argument>/get_dicom.pl.<UNIX_process_number>
          For example with -d /data/tmp, the DICOM files will be extracted in 
          /data/tmp/get_dicom.pl.67888 (assuming 67888 is the process number). By default, dir_argument
          is set to /tmp.
-o      : basename of the final tar.gz file to produce, in the current directory (defaults to dicoms.tar.gz)

=head1 DESCRIPTION

This script first connects to the database to build the list of tarchives for which
the patient names match the list of patterns specified as argument. The script will then examine 
these tarchives and look for the MINC files whose scan types (acquisition protocol names) match 
the list of patterns passed as argument. It then extracts the DICOM files associated to each
MINC file and writes them in the extraction directory (see -d option), in a subdirectory with name

<pscid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>

where <minc_index> is the index number of the MINC file to which the DICOMs are associated.
Finally, a tar is created which contains all the DICOM files that were extract

=head2 Methods

=cut

use NeuroDB::DBI;
use NeuroDB::ExitCodes;

use File::Path;
use File::Basename;
use Getopt::Tabular;

#-----------------------------------------------#
# Triggers the deletion of the tmp extract dir  #
# if something like CTRL-C is pressed during    #
# execution of the script                       #
#-----------------------------------------------#
use sigtrap 'handler' => \&rmTmpExtractDir, 'normal-signals';

my $patientNames;
my $scanTypes;
my $profile           = 'prod';
my $tmpExtractBaseDir = '/tmp';
my $outTarBasename    = 'dicoms';

my @opt_table           = (
    ["-p", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"],
    ["-n", "string", 1,   \$patientNames, 
        "comma-separated list of MySQL patterns for the patient name"],
    ["-t", "string", 1,   \$scanTypes, 
        "comma-separated list of MySQL patterns for the scan type"],
    ["-d", "string", 1,   \$tmpExtractBaseDir, 
        "base path of the temporary directory where files are extracted (defaults to /tmp)"],   
    ["-o", "string", 1,   \$outTarBasename, 
        "base path of the final .tar.gz file to produce (defaults to 'dicoms')"],   
);

my $Help = <<HELP;

get_dicom.pl - extracts DICOM files for specific patient names/scan types

This script first connects to the database to build the list of tarchives for which
the patient names match the list of patterns specified as argument. The script will then examine 
these tarchives and look for the MINC files whose scan types (acquisition protocol names) match 
the list of patterns passed as argument. Once this is done, a tar file is built for each MINC 
file containing the DICOM files associated with it. Each tar file is written in the extraction 
directory(see -d option), in a subdirectory with name

<pscid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>

where <minc_index> is the index number of the MINC file for which the tar is produced.
Finally, a tar is created which contains all the DICOM files that were extract

HELP
my $Usage = <<USAGE;
perl get_dicom.pl [-p profile] [-n patient_name_patterns] [-t scan_type_patterns] [-d tmp_dir] [-o tarBasename]
USAGE


&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;
my @patientNames = defined $patientNames ? split(',', $patientNames) : ();
my @scanTypes    = defined $scanTypes    ? split(',', $scanTypes)    : ();

#---------------------------------------#
# Read prod file to get DB credentials  #
#---------------------------------------#
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if(!@Settings::db) {
    die "No database settings in file $ENV{LORIS_CONFIG}/.loris_mri/$profile\n";
}
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

#-------------------------------------------#
# Fetch tarchiveLibraryDir from the config  #
#-------------------------------------------#
my $sth = $dbh->prepare(
     "SELECT Value "
   . "FROM Config c "
   . "JOIN ConfigSettings cs ON (cs.ID=c.ConfigID) "
   . "WHERE cs.Name = ?"
);
$sth->execute('tarchiveLibraryDir');

my($tarchiveLibraryDir) = $sth->fetchrow_array;

#------------------------------------------------------------#
# Get the list of tarchives for which the patient names      #
# match the list of supplied patterns                        #
#------------------------------------------------------------#
my $stmt = "SELECT c.pscid, s.visit_label, t.dateacquired, t.archivelocation, t.tarchiveid, t.patientname "
         . "FROM tarchive t "
         . "JOIN session s ON (t.sessionid=s.id) "
         . "JOIN candidate c ON (c.candid=s.candid) ";
if(@patientNames) {
	my @where = map { "t.patientname LIKE ?" } @patientNames;
	$stmt .= sprintf("WHERE %s", join("OR", @where));
}
$sth = $dbh->prepare($stmt);

if(@patientNames) {
    for(my $p=0; $p<@patientNames; $p++) {
        $sth->bind_param($p+1, $patientNames[$p]);
    }
}
$sth->execute();

#----------------------------------------------------------#
# Create the directory where DICOM files will be extracted #
#----------------------------------------------------------#
my $tmpExtractDir = sprintf("%s/%s.%d", $tmpExtractBaseDir, basename($0), $$);
mkdir $tmpExtractDir or die "Cannot create directory $tmpExtractDir: $!\n";

#---------------------------------------------------------#
# Process each tarchive and extract the DICOMs associated #
# to the scan types of interest                           #
#---------------------------------------------------------#
my @outDirs = ();
foreach my $tarchiveRowRef (@{ $sth->fetchall_arrayref }) {
    my($pscid, $visitLabel, $dateAcquired, $archiveLocation, $tarchiveId) = @$tarchiveRowRef;
    
    my($innerTar) = "$archiveLocation.gz" =~ /_(ImagingUpload.*.tar.gz)$/;
    
    # Extract only the .tar.gz archive from the main archive (ignore the 
    # meta data and log file)
    print "Extracting $innerTar in $tmpExtractDir...";
    system("tar xf $tarchiveLibraryDir/$archiveLocation -C $tmpExtractDir $innerTar") == 0 
      or die "Extraction of $innerTar from $tarchiveLibraryDir/$archiveLocation in directory $tmpExtractDir failed: $?";
    print "done\n";
    
    # Fetch all the MINC files in the archive whose acquisition protocols
    # match the scan types of interest
    $stmt = "SELECT f.file, tf.filename "
          . "FROM files f "
          . "JOIN mri_scan_type mst ON (mst.id=f.acquisitionprotocolid) "
          . "JOIN tarchive_files tf ON (tf.tarchiveid=f.tarchivesource) "
          . "WHERE tarchivesource = ?"; 
	my @where = map { "mst.scan_type LIKE ?" } @scanTypes;
	$stmt .= sprintf(" AND (%s)", join("OR", @where)) if @where;
	$sth = $dbh->prepare($stmt);
	$sth->execute($tarchiveId, @scanTypes);

    # For each MINC file X, find the names of the DICOM files that have the
    # same SeriesDescriptionUID as X and store them in @{ $filesRef->{$mincFile} }
    my $filesRef = {};
    foreach my $fileRowRef (@{ $sth->fetchall_arrayref }) {
		my($mincFile, $dicomFilename) = @$fileRowRef;
		    
		$filesRef->{$mincFile} = [] unless defined $filesRef->{$mincFile};
		push(@{ $filesRef->{$mincFile} }, $dicomFilename);
	}
	
	# Foreach MINC file build a tar file with the set of DICOM files
	# that were used to produce it (found above)
	foreach my $file (keys %$filesRef) {
		# Build file that contains the list of paths of the DICOM files to
		# extact from the archive
        my @dicomFilePatterns = map { "*/$_" } @{ $filesRef->{$file} };
        my($fileBaseName) = $file =~ /\/([^\/]+).mnc$/;
        my $fileList = "$tmpExtractDir/$fileBaseName.dicom";
        open(FILE_LIST, ">$fileList") or die "Cannot write file $fileList: $!\n";
        foreach( @dicomFilePatterns) {
			print FILE_LIST "$_\n";
		}
		close(FILE_LIST);
		
		# Create a tar file containing the specified DICOMs
        my($outSubDir) = $file =~ /_(\w+_\d+).mnc$/;
        my $outDir = "$tmpExtractDir/$pscid/$visitLabel/$dateAcquired/$outSubDir";
		my $cmd = "tar xf $tmpExtractDir/$innerTar"
		        . " --no-recursion "
		        . " --wildcards"
		        . " --files-from=$fileList "
		        . " --absolute-names "
		        . " --transform='s#^.*/#$outDir/#'";
		print "Extracting DICOM files for $file...";
		system($cmd) == 0 
		    or die "Failed to extract DICOM files for MINC file $file from $tmpExtractDir/$innerTar: $?\n";
		print "done.\n";
		
		push(@outDirs, "$pscid/$visitLabel/$dateAcquired/$outSubDir");
	}
}

# Make a big tar of all this
my $outTarFile = "$outTarBasename.tar.gz";
my $outDirsFile = "$tmpExtractDir/out_dirs.$$.txt";
open(OUT_DIRS_FILE, ">$outDirsFile") or die "Cannot write to file $outDirsFile: $!\n";
foreach(@outDirs) {
	print OUT_DIRS_FILE "$_\n";
}
close(OUT_DIRS_FILE);

print "Writing $outTarFile...";
my $cmd = "tar zcf $outTarFile -C $tmpExtractDir --files-from=$outDirsFile";
system($cmd) == 0 or die "Failed to archive DICOM files in $outTarFile: $?\n";
print "done\n";

exit $NeuroDB::ExitCodes::SUCCESS;

#-----------------------------------------------------#
# This will erase the tmp extract dir when the script #
# terminates (either normally or abnormally)          #
#-----------------------------------------------------#
END { &rmTmpExtractDir() }

#==========================#
#                          #
#       SUBROUTINES        #
#                          #
#==========================#

=pod

=head3 rmTmpExtractDir()

Function that deletes directory $tmpExtractDir and all its contents if 
variable $tmpExtractDir is defined. 

=cut
sub rmTmpExtractDir 
{
	if(defined $tmpExtractDir) {
		print "Deleting directory $tmpExtractDir and contents...";
	    rmtree($tmpExtractDir);
	    print "done\n";
	}
}


