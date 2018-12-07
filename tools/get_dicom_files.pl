#!/usr/bin/perl -w 
use strict;

=pod

=head1 NAME

get_dicom_files.pl - extracts DICOM files for specific patient names/scan types

=head1 SYNOPSIS

perl get_dicom_files.pl [-n patient_name_patterns] [-t scan_type_patterns] [-d tmp_dir] [-o tarBasename] -profile profile

Available options are:

-profile : name of the config file in C<../dicom-archive/.loris_mri> (typically C<prod>)

-n       : comma separated list of MySQL patterns for the patient names that a DICOM file
           has to have in order to be extracted. A DICOM file only has to match one of the 
           patterns to be extracted. If no pattern is specified, then the patient name is 
           not used to determine which DICOM files to extract. This option must be used if
           no scan type patterns were specified with C<-t> (see below).
          
-t       : comma separated list of MySQL patterns of the acquisition protocols (scan types
           names) that a DICOM file has to have in order to be extracted. A DICOM file only
           has to match one of the patterns to be extracted. If no pattern is specified, then
           the scan type name is not used to determine which DICOM files to extract. This option
           must be used if no patient name patterns were specified via C<-n> (see above).
          
-d       : extract the files in directory C<< <dir_argument>/get_dicom_files.pl.<UNIX_process_number> >>
           For example with C<-d /data/tmp>, the DICOM files will be extracted in 
           C</data/tmp/get_dicom_files.pl.67888> (assuming 67888 is the process number). 
           By default, dir_argument is set to the value of the environment variable C<TMPDIR>.
          
-o       : basename of the final C<tar.gz> file to produce, in the current directory (defaults to 
           C<dicoms.tar.gz>).

=head1 DESCRIPTION

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument, or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if C<-t> was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see C<-d> option), in a 
subdirectory with name

C<< <pscid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index> >>

where C<< <minc_index> >> is the index number of the MINC file to which the DICOMs are associated: 
e.g. for file C<loris_300001_V4_DtiSA_002.mnc>, the MINC index is 2 (i.e. the second MINC file with 
scan type C<DtiSA>). Finally, a C<.tar.gz> that contains all the DICOM files that were extracted is 
created.

=head2 Methods

=cut

use NeuroDB::DBI;
use NeuroDB::ExitCodes;

use File::Path;
use File::Basename;
use File::Temp qw/tempdir/;

use Getopt::Tabular;

#-----------------------------------------------#
# Triggers the deletion of the tmp extract dir  #
# if something like CTRL-C is pressed during    #
# execution of the script                       #
#-----------------------------------------------#

my $patientNames;
my $scanTypes;
my $profile;
my $tmpExtractBaseDir;
my $outTarBasename    = 'dicoms';

my @opt_table           = (
    ["-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"],
    ["-n", "string", 1,   \$patientNames, 
        "comma-separated list of MySQL patterns for the patient name"],
    ["-t", "string", 1,   \$scanTypes, 
        "comma-separated list of MySQL patterns for the scan type"],
    ["-d", "string", 1,   \$tmpExtractBaseDir, 
        "base path of the temporary directory where files are extracted"],   
    ["-o", "string", 1,   \$outTarBasename, 
        "base path of the final .tar.gz file to produce (defaults to 'dicoms')"],   
);

my $Help = <<HELP;

get_dicom_files.pl - extracts DICOM files for specific patient names/scan types

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if -t was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see -d option), in a 
subdirectory with name

<pscid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>

where <minc_index> is the index number of the MINC file to which the DICOMs are associated: e.g. for
file 'loris_300001_V4_DtiSA_002.mnc', the MINC index is 2 (i.e. the second MINC file with scan type
'DtiSA'). Finally, a '.tar.gz' that contains all the DICOM files that were extracted is created.

HELP
my $Usage = <<USAGE;
#~ perl get_dicom_files.pl [-n patient_name_patterns] [-t scan_type_patterns] [-d tmp_dir] [-o tarBasename] -profile profile
USAGE


&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;
$tmpExtractBaseDir = $tmpExtractBaseDir // $ENV{'TMPDIR'} // undef;
die "You must use either the -n or -t option, or both. Aborting.\n" 
    if !defined $patientNames && !defined $scanTypes;
if(!defined $tmpExtractBaseDir or $tmpExtractBaseDir !~ /\S/) {
    die "The '-d' option was not used and the environment variable TMPDIR is not defined. Aborting.\n";
}
 
#---------------------------------------#
# Read prod file to get DB credentials  #
#---------------------------------------#
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -p argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if(!@Settings::db) {
    die "No database settings in file $ENV{LORIS_CONFIG}/.loris_mri/$profile\n";
}

my @patientNames       = defined $patientNames ? split(',', $patientNames) : ();
my @scanTypes          = defined $scanTypes    ? split(',', $scanTypes)    : ();
my $dbh                = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $tarchiveLibraryDir = NeuroDB::DBI::getConfigSetting(\$dbh, 'tarchiveLibraryDir');

#----------------------------------------------------------#
# Create the directory where DICOM files will be extracted #
#----------------------------------------------------------#
my $tmpExtractDir = tempdir("$0.XXXX", DIR => $tmpExtractBaseDir, CLEANUP => 1);
#my $tmpExtractDir = sprintf("%s/%s.%d", $tmpExtractBaseDir, basename($0), $$);
#mkdir $tmpExtractDir or die "Cannot create directory $tmpExtractDir: $!\n";

#------------------------------------------------------------#
# Get the list of tarchives for which the patient names      #
# match the list of supplied patterns (or all tarchives if   #
# no patterns were specified)                                #
#------------------------------------------------------------#
my $query = "SELECT c.PSCID, s.Visit_label, t.DateAcquired, t.ArchiveLocation, t.TarchiveID, t.PatientName "
          . "FROM tarchive t "
          . "JOIN session s ON (t.SessionID=s.ID) "
          . "JOIN candidate c ON (c.CandID=s.CandID) ";
if(@patientNames) {
    my @where = map { "t.PatientName LIKE ?" } @patientNames;
    $query .= sprintf("WHERE (%s)", join(" OR ", @where));
}
my $sth = $dbh->prepare($query);

if(@patientNames) {
    for(my $p=0; $p<@patientNames; $p++) {
        $sth->bind_param($p+1, $patientNames[$p]);
    }
}
$sth->execute();

#---------------------------------------------------------#
# Process each tarchive and extract the DICOMs associated #
# to the scan types of interest                           #
#---------------------------------------------------------#
my @outDirs = ();
foreach my $tarchiveRowRef (@{ $sth->fetchall_arrayref }) {
    my($pscid, $visitLabel, $dateAcquired, $archiveLocation, $tarchiveId) = @$tarchiveRowRef;
    
    # Extract only the .tar.gz archive from the main archive (ignore the 
    # meta data and log file)
    print "Extracting compressed archive contained in $tarchiveLibraryDir/$archiveLocation...";
    system("tar xf $tarchiveLibraryDir/$archiveLocation -C $tmpExtractDir --wildcards \\*.tar.gz") == 0 
      or die "Extraction of compressed archive from $tarchiveLibraryDir/$archiveLocation in directory $tmpExtractDir failed: $?";
    print "done\n";
    
    # Fetch all the MINC files created out of the DICOM archive whose 
    # acquisition protocols match the scan types
    # of interest
    $query = "SELECT f.File, tf.FileName "
           . "FROM files f "
           . "JOIN mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID) "
           . "JOIN tarchive_series ts ON (f.SeriesUID=ts.SeriesUID AND f.EchoTime*1000=ts.EchoTime) "
           . "JOIN tarchive_files tf USING (TarchiveSeriesID) "
           . "WHERE f.TarchiveSource = ?";
    my @where = map { "mst.Scan_type LIKE ?" } @scanTypes;
    $query .= sprintf(" AND (%s)", join(" OR ", @where)) if @where;
    $sth = $dbh->prepare($query);
    $sth->execute($tarchiveId, @scanTypes);

    # For each MINC file X, find the names of the DICOM files that have the
    # same SeriesDescriptionUID as X and store them in @{ $filesRef->{$mincFile} }
    my $filesRef = {};
    foreach my $fileRowRef (@{ $sth->fetchall_arrayref }) {
        my($mincFile, $dicomFilename) = @$fileRowRef;
        chomp $dicomFilename;
            
        $filesRef->{$mincFile} = [] unless defined $filesRef->{$mincFile};
        push(@{ $filesRef->{$mincFile} }, $dicomFilename);
    }
    
    # Foreach MINC file extract the set of DICOM files
    # that were used to produce it (found above)
    foreach my $file (keys %$filesRef) {
        # Build file that contains the list of paths of the DICOM files to
        # extact from the archive
        my($fileBaseName) = $file =~ /\/([^\/]+).mnc$/;
        my $fileList = "$tmpExtractDir/$fileBaseName.dicom";
        open(FILE_LIST, ">$fileList") or die "Cannot write file $fileList: $!\n";
        
        open(LIST_TAR_CONTENT, "tar ztf $tmpExtractDir/*.tar.gz|") 
            or die "Cannot run command tar tf $tmpExtractDir/*.tar.gz:$?\n";
        while (<LIST_TAR_CONTENT>) {
            chomp;
            my($fileName, $dirName, $suffix) = fileparse($_);
            print FILE_LIST "$_\n" if grep($_ eq $fileName, @{ $filesRef->{$file} });
        }
        close(FILE_LIST);
        close(LIST_TAR_CONTENT);
        
        # Extract from the inner tar the DICOMs who names are listed in
        # $tmpExtractDir/$fileBaseName.dicom
        my($outSubDir) = $file =~ /_([^_]+_\d+).mnc$/;
        my $outDir = "$tmpExtractDir/$pscid/$visitLabel/$dateAcquired/$outSubDir";
        
        # --files-from: file containing the path of the files to extract
        # --transform: put all extracted files in $outDir
        # --absolute-path: since we are extracting in $outDir and since
        #                  $outDir is an absolute path, we need this option otherwise
        #                  tar will refuse to extract
        my $cmd = "tar zxf $tmpExtractDir/*.tar.gz"
                . " --files-from=$fileList "   
                . " --absolute-names "
                . " --transform='s#^.*/#$outDir/#'";
        print "Extracting DICOM files for $file...";
        system($cmd) == 0 
            or die "Failed to extract DICOM files for MINC file $file from archive in $tmpExtractDir: $?\n";
        print "done.\n";
        
        push(@outDirs, "$pscid/$visitLabel/$dateAcquired/$outSubDir");
    }
}

if(!@outDirs) {
    print "No DICOM files match the specified criterias specifed via -t and/or -n. No .tar.gz file created.\n";
} else {
    # Make a big tar of all the extracted DICOMs that match the patient name patterns
    # and scan type name patterns
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
}

exit $NeuroDB::ExitCodes::SUCCESS;
