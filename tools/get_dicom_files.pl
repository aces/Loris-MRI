#!/usr/bin/perl -w 
use strict;

=pod

=head1 NAME

get_dicom_files.pl - extracts DICOM files for specific patient names/scan types

=head1 SYNOPSIS

perl get_dicom_files.pl [-names patient_name_patterns] [-types scan_type_patterns] [-outdir tmp_dir] [-outfile tarBasename] 
           [-id candid|pscid|candid_pscid|pscid_candid] -profile profile

Available options are:

-profile : name of the config file in C<../dicom-archive/.loris_mri> (typically C<prod>)

-names   : comma separated list of MySQL patterns for the patient names that a DICOM file
           has to have in order to be extracted. A DICOM file only has to match one of the 
           patterns to be extracted. If no pattern is specified, then the patient name is 
           not used to determine which DICOM files to extract. This option must be used if
           no scan type patterns were specified with C<-type> (see below).
          
-types   : comma separated list of MySQL patterns of the acquisition protocols (scan types
           names) that a DICOM file has to have in order to be extracted. A DICOM file only
           has to match one of the patterns to be extracted. If no pattern is specified, then
           the scan type name is not used to determine which DICOM files to extract. This option
           must be used if no patient name patterns were specified via C<-names> (see above).
          
-outdir  : extract the files in directory C<< <dir_argument>/get_dicom_files.pl.<random_string> >>
           For example with C<-d /data/tmp>, the DICOM files might be extracted in 
           C</data/tmp/get_dicom_files.pl.n1d4>. By default, dir_argument is set to the value of
           the environment variable C<TMPDIR>. Since the UNIX program C<tar> has known limitations 
           with NFS file systems (incorrect reports of files that changed while they are archived), the
           argument to C<-d> should not be a directory that resides on an NFS mounted file system.
           Failure to do so might result in C<get_dicom_files.pl> failing.
          
-outfile : basename of the final C<tar.gz> file to produce, in the current directory (defaults to 
           C<dicoms.tar.gz>).
           
-id      : how to name the subdirectory identifying the candidate to which the DICOM files belong:
           pscid, candid, pscid_candid or candid_pscid (defaults to candid)

=head1 DESCRIPTION

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument, or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if C<-types> was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see C<-outdir> option), in a 
subdirectory with name

C<< <dccid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>_<series_description >>

where C<< <minc_index> >> is the index number of the MINC file to which the DICOMs are associated: 
e.g. for file C<loris_300001_V4_DtiSA_002.mnc>, the MINC index is 2 (i.e. the second MINC file with 
scan type C<DtiSA>). Note that the C<dccid> subdirectory in the file path can be changed to another
identifier with option C<-id>. Finally, a C<.tar.gz> that contains all the DICOM files that were extracted
is created.

=cut

use NeuroDB::DBI;
use NeuroDB::ExitCodes;

use File::Path;
use File::Basename;
use File::Temp qw/tempdir/;
use File::Path 'rmtree';

use Getopt::Tabular;
&Getopt::Tabular::AddPatternType(
    "candidate_identifier", 
    "pscid|candid|pscid_candid|candid_pscid", 
    "one of the sdtrings 'pscid', 'candid' , 'pscid_candid' or 'candid_pscid'"
);

# If the absolute value of the difference between two floating 
# point numbers is lower than this, the two numbers are considered
# equal
my $FLOAT_EQUALS_THRESHOLD = 0.00001;

my $patientNames;
my $scanTypes;
my $profile;
my $tmpExtractBaseDir;
my $outTarBasename      = 'dicoms';
my $candidateIdentifier = 'candid';

my @opt_table           = (
    ["-profile", "string"              , 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"],
    ["-name"   , "string"              , 1, \$patientNames, 
        "comma-separated list of MySQL patterns for the patient name"],
    ["-type"   , "string"              , 1, \$scanTypes, 
        "comma-separated list of MySQL patterns for the scan type"],
    ["-outdir" , "string"              , 1, \$tmpExtractBaseDir, 
        "base path of the temporary directory where files are extracted"],   
    ["-outfile", "string"              , 1, \$outTarBasename, 
        "basename of the final .tar.gz file to produce (defaults to 'dicoms.tar.gz')"], 
    ["-id"     , "candidate_identifier", 1, \$candidateIdentifier, 
          "how to name the subdirectory identifying the candidate to which the DICOM files belong:"
        . "one of pscid, candid, pscid_candid or candid_pscid (defaults to candid)"]
);

my $Help = <<HELP;

get_dicom_files.pl - extracts DICOM files for specific patient names/scan types

This script first connects to the database to build the list of DICOM archives for which
the patient names match the list of patterns specified as argument or all DICOM archives if
no patterns were specified. The script will then examine these DICOM archives and look for the 
MINC files whose scan types (acquisition protocol names) match the list of patterns passed as 
argument, or all MINC files for that archive if -type was not used. It then extracts the DICOM files
associated to each MINC file and writes them in the extraction directory (see -outdir option), in a 
subdirectory with name

<dccid>/<visit_label>/<acquisition_date>/<protocol>_<minc_index>_<series_description>

where <minc_index> is the index number of the MINC file to which the DICOMs are associated: e.g. for
file 'loris_300001_V4_DtiSA_002.mnc', the MINC index is 2 (i.e. the second MINC file with scan type
'DtiSA'). Note that the dccid subdirectory in the file path can be changed to another identifier with 
option -id. Finally, a '.tar.gz' that contains all the DICOM files that were extracted is created.

HELP
my $Usage = <<USAGE;
#~ perl get_dicom_files.pl [-name patient_name_patterns] [-type scan_type_patterns] [-outdir tmp_dir] 
      [-outfile tarBasename] [-id pscid|candid|pscid_candid|candid_pscid] -profile profile
USAGE


&Getopt::Tabular::SetHelp( $Help, $Usage );
&Getopt::Tabular::GetOptions( \@opt_table, \@ARGV )
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;
$tmpExtractBaseDir = $tmpExtractBaseDir // $ENV{'TMPDIR'} // undef;
die "You must use either the -name or -type option, or both. Aborting.\n" 
    if !defined $patientNames && !defined $scanTypes;
if(!defined $tmpExtractBaseDir or $tmpExtractBaseDir !~ /\S/) {
    die "The '-outdir' option was not used and the environment variable TMPDIR is not defined. Aborting.\n";
}
 
#---------------------------------------#
# Read prod file to get DB credentials  #
#---------------------------------------#
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
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
$tarchiveLibraryDir =~ s#\/$##;

#----------------------------------------------------------#
# Create the directory where DICOM files will be extracted #
#----------------------------------------------------------#
my $tmpExtractDir = tempdir("$0.XXXX", DIR => $tmpExtractBaseDir, CLEANUP => 1);

#------------------------------------------------------------#
# Get the list of tarchives for which the patient names      #
# match the list of supplied patterns and/or the list of     #
# scan type patterns                                         #
#------------------------------------------------------------#
my $query = "SELECT c.PSCID, c.CandID, s.Visit_label, t.DateAcquired, t.ArchiveLocation, t.TarchiveID, t.PatientName "
          . "FROM tarchive t "
          . "JOIN session s ON (t.SessionID=s.ID) "
          . "JOIN candidate c ON (c.CandID=s.CandID) "
          . "WHERE 1=1";
          
# Add patient name clause (if any)          
if(@patientNames) {
    my @where = map { "t.PatientName LIKE ?" } @patientNames;
    $query .= sprintf(" AND (%s)", join(" OR ", @where));
}

# Add scan type clause (if any)
if(@scanTypes) {
    my @where = map { "mst.Scan_type LIKE ?" } @scanTypes;
    
    # This query will return 1 iff the archive contains at least one
    # file with a scan type whose name matches the conditions imposed
    # via -t
    my $innerQuery = "SELECT 1 "
                   . "FROM files f "
                   . "JOIN mri_scan_type mst ON(mst.ID=f.AcquisitionProtocolID) "
                   . "WHERE f.TarchiveSource=t.TarchiveID "
                   . "AND (" . join(" OR " , @where) . ")";
    $query .= " AND EXISTS($innerQuery)";
}
my $sth = $dbh->prepare($query);

# Bind patient name patterns placeholders to their actual values
if(@patientNames) {
    for(my $p=0; $p<@patientNames; $p++) {
        $sth->bind_param($p+1, $patientNames[$p]);
    }
}

# Bind scan type patterns placeholders to their actual values
if(@scanTypes) {
    for(my $t=0; $t<@scanTypes; $t++) {
        my $placeHolderIndex = $t + scalar(@patientNames) + 1;
        $sth->bind_param($placeHolderIndex, $scanTypes[$t]);
    }
}
$sth->execute();

#---------------------------------------------------------#
# Process each tarchive and extract the DICOMs associated #
# to the scan types of interest                           #
#---------------------------------------------------------#
my $nbDirsArchived = 0;
my $outTarFile = "$outTarBasename.tar";
foreach my $tarchiveRowRef (@{ $sth->fetchall_arrayref }) {
    my($pscid, $candid, $visitLabel, $dateAcquired, $archiveLocation, $tarchiveId) = @$tarchiveRowRef;
    
    my($innerTar) = $archiveLocation =~ /\/DCM_\d+-\d+-\d+_([^\/]+)\.tar$/;
    $innerTar .= '.tar.gz';
    
    # Extract only the .tar.gz archive from the main archive (ignore the 
    # meta data and log file)
    print "Extracting $innerTar in $tmpExtractDir...";
    my $cmd = sprintf(
        "tar xf %s/%s -C %s %s",
        quotemeta($tarchiveLibraryDir),
        quotemeta($archiveLocation),
        quotemeta($tmpExtractDir),
        quotemeta($innerTar)
    );
    system($cmd) == 0 or die "Extraction of '$innerTar' in '$tmpExtractDir' failed: $?";
    print "done\n";
    
    # Fetch all the MINC files created out of the DICOM archive whose 
    # acquisition protocols match the scan types
    # of interest
    $query = "SELECT DISTINCT f.File, tf.FileName, ts.SeriesDescription "
           . "FROM files f "
           . "JOIN mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID) "
           . "JOIN tarchive_series ts ON (f.SeriesUID=ts.SeriesUID AND ABS(f.EchoTime*1000 - ts.EchoTime) < $FLOAT_EQUALS_THRESHOLD) "
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
        my($mincFile, $dicomFilename, $seriesDescription) = @$fileRowRef;
        chomp $dicomFilename;
            
        $filesRef->{$mincFile}->{'SeriesDescription'} = $seriesDescription;
        $filesRef->{$mincFile}->{'DICOM'}             = [] unless defined $filesRef->{$mincFile}->{'DICOM'};
        push(@{ $filesRef->{$mincFile}->{'DICOM'} }, $dicomFilename);
    }
    
    # Foreach MINC file extract the set of DICOM files
    # that were used to produce it (found above)
    foreach my $file (keys %$filesRef) {
        # Build file that contains the list of paths of the DICOM files to
        # extact from the archive
        my($fileBaseName) = $file =~ /\/([^\/]+).mnc$/;
        my $fileList = "$tmpExtractDir/$fileBaseName.dicom";
        open(FILE_LIST, ">$fileList") or die "Cannot write file $fileList: $!\n";
        
        my $tarCmd = sprintf("tar ztf %s/%s", quotemeta($tmpExtractDir), quotemeta($innerTar));
        open(LIST_TAR_CONTENT, "$tarCmd|") or die "Cannot run command $tarCmd: $?\n";
        while (<LIST_TAR_CONTENT>) {
            chomp;
            my($fileName, $dirName, $suffix) = fileparse($_);
            print FILE_LIST "$_\n" if grep($_ eq $fileName, @{ $filesRef->{$file}->{'DICOM'} });
        }
        close(FILE_LIST);
        close(LIST_TAR_CONTENT);
        
        # Extract from the inner tar the DICOMs who names are listed in
        # $tmpExtractDir/$fileBaseName.dicom
        my($outSubDir) = $file =~ /_([^_]+_\d+).mnc$/;
        $outSubDir .= sprintf("_%s", $filesRef->{$file}->{'SeriesDescription'});
        
        # Determine the identifier or combination of identifiers to use as part of
        # the file name
        my $id;
        $id = "$pscid"             if $candidateIdentifier eq 'pscid';
        $id = "${pscid}_${candid}" if $candidateIdentifier eq 'pscid_candid';
        $id = "$candid"            if $candidateIdentifier eq 'candid';
        $id = "${candid}_${pscid}" if $candidateIdentifier eq 'candid_pscid';

        my $outDir = "$tmpExtractDir/$id/$visitLabel/$dateAcquired/$outSubDir";
        
        # --files-from: file containing the path of the files to extract
        # --transform: put all extracted files in $outDir
        # --absolute-path: since we are extracting in $outDir and since
        #                  $outDir is an absolute path, we need this option otherwise
        #                  tar will refuse to extract
        $cmd = sprintf(
            "tar zxf %s/%s --files-from=%s --absolute-names --transform='s#^.*/#$outDir/#'",
            quotemeta($tmpExtractDir),
            quotemeta($innerTar),
            quotemeta($fileList) 
        );
        print "Extracting DICOM files for $file...";
        system($cmd) == 0 
            or die "Failed to extract DICOM files for MINC file $file from $tmpExtractDir/$innerTar: $?\n";
        print "done.\n";

        # Set archiving mode to 'create' or 'append' depending on whether
        # this is the first file archived or not
        my $tarOptions = $nbDirsArchived ? 'rf' : 'cf';
        $cmd = sprintf(
            "tar $tarOptions %s -C %s --absolute-names %s",
            quotemeta($outTarFile),
            quotemeta($tmpExtractDir),
            quotemeta("$id/$visitLabel/$dateAcquired/$outSubDir")
        );
        print "Archiving $outDir...";
        system($cmd) == 0 or die "Failed to write DICOM files found in $outDir in archive $outTarFile: $?\n";
        print "done\n";
        $nbDirsArchived++;

        # Delete the outDir every time so that the temporary extract dir does not grow too big
        rmtree($outDir);
        unlink($fileList) or warn "Warning! Could not delete '$tmpExtractDir/$innerTar'\n";
    }
   
    unlink("$tmpExtractDir/$innerTar") or warn "Warning! Could not delete '$tmpExtractDir/$innerTar'\n";
}

if(!$nbDirsArchived) {
    print "No DICOM files match the criteria specifed via -t and/or -n. No .tar.gz file created.\n";
} else {
    my $cmd = sprintf("gzip -f %s", quotemeta($outTarFile));
    system($cmd) == 0 or die "Failed to run $cmd\n";
    printf("Wrote %s.gz\n", $outTarFile);
}

exit $NeuroDB::ExitCodes::SUCCESS;
