#! /usr/bin/perl

=pod

=head1 NAME

run_defacing.pl -- a script that creates defaced images for anatomical
acquisitions specified in the Config module of LORIS.


=head1 SYNOPSIS

C<perl tools/run_defacing_script.pl [options]>

Available options are:

C<-profile>     : name of the config file in C<../dicom-archive/.loris_mri>

C<-tarchive_ids>: comma-separated list of MySQL C<TarchiveID>s

C<-verbose>     : be verbose


=head1 DESCRIPTION

This script will create defaced images for anatomical acquisitions that are
specified in the Config module of LORIS.


=head1 METHODS

=cut


use strict;
use warnings;
use Getopt::Tabular;
use File::Basename;
use File::Path 'make_path';
use File::Temp 'tempdir';


use NeuroDB::DBI;
use NeuroDB::ExitCodes;



# These are hardcoded as examples of how to deal with special modalities:
# - Siemens field-map modality produces a phase and two magnitude files. Only the
#   magnitude images should be defaced (no face on the phase image).
# - MP2RAGE inversion scans produces a distortion and a normalized image, only the
#   normalized image should be defaced (no face on the distortion image).
# - quantitative multi-echo T2star produces a phase and a magnitude image for each
#   echo. In that case, only the magnitude files should be defaced (no face on the
#   phase image so should not deface)
# The %SPECIAL_ACQUISITIONS_FILTER variable has been created to filter out the
# correct FileIDs of the images that need to be defaced for those special modalities
my %SPECIAL_ACQUISITIONS_FILTER = (
    'fieldmap'      => 'ORIGINAL\\PRIMARY\\M\\ND',
    'MP2RAGEinv1'   => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\ND\\NORM',
    'MP2RAGEinv2'   => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\ND\\NORM',
    'qT2starEcho1'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho2'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho3'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho4'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho5'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho6'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho7'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho8'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho9'  => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho10' => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho11' => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND',
    'qT2starEcho12' => 'ORIGINAL\\\\\\\\PRIMARY\\\\\\\\M\\\\\\\\ND'
);

# The @MULTI_CONTRAST_ACQUISITIONS_BASE_NAMES variable will store the base names
# of multi-contrast acquisitions such as MP2RAGE, qT2star or fieldmap. These will
# allow to call the deface_minipipe.pl tool properly for multi-contrast
# acquisition (a.k.a. fieldmap_file1,fieldmap_file2) which will tell the
# deface_minipipe.pl script to not create 2 XFMs but instead reuse the XFM from
# fieldmap_file1 to register fieldmap_file2
my @MULTI_CONTRAST_ACQUISITIONS_BASE_NAMES = ( "fieldmap", "MP2RAGE", "qT2star" );




my $profile;
my $session_ids;
my $verbose          = 0;
my $profile_desc     = "Name of the config file in ../dicom-archive/.loris_mri";
my $session_ids_desc = "Comma-separated list of SessionIDs on which to run the "
                       . "defacing algorithm (if not set, will deface images for "
                       . "all SessionIDs present in the database)";

my @opt_table = (
    [ "-profile",    "string",  1, \$profile,     $profile_desc      ],
    [ "-sessionIDs", "string",  1, \$session_ids, $session_ids_desc ],
    [ "-verbose",    "boolean", 1, \$verbose,     "Be verbose"       ]
);

my $Help = <<HELP;
**********************************************************************************
DEFACE ANATOMICAL SCANS BASED ON SCAN TYPES TO DEFACE IN THE CONFIGURATION MODULE
**********************************************************************************

This script will run the defacing algorithm on anatomical scan types listed in the
compute_defaced_images of the imaging pipeline section of the configuration module.

If a list of SessionIDs is provided using the option -sessionIDs, then the defacing
algorithm will be run restricted to MINC files belonging to those SessionIDs.

If -sessionIDs is not set, the defacing algorithm will be run on MINC files
belonging to all SessionIDs present in the database.

Documentation: perldoc run_defacing_script.pl

HELP

my $Usage = <<USAGE;
Usage: $0 [options]
       $0 -help to list options
USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;



## input error checking

if (!$ENV{LORIS_CONFIG}) {
    print STDERR "\n\tERROR: Environment variable 'LORIS_CONFIG' not set\n\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR;
}

if (!defined $profile || !-e "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
    print $Help;
    print STDERR "$Usage\n\tERROR: You must specify a valid and existing profile.\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}



## establish database connection

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to the database \n" if $verbose;



## get config settings

my $ref_scan_type = &NeuroDB::DBI::getConfigSetting(\$dbh, 'reference_scan_type_for_defacing');
my $to_deface     = &NeuroDB::DBI::getConfigSetting(\$dbh, 'modalities_to_deface'            );
my $data_dir      = &NeuroDB::DBI::getConfigSetting(\$dbh, 'dataDirBasepath'                 );
$data_dir         =~ s/\/$//;  # remove trailing /
unless ($ref_scan_type && $to_deface) {
    print STDERR "\n==> ERROR: you need to configure both the "
                 . "reference_scan_type_for_defacing & modalities_to_deface config "
                 . "settings in the imaging pipeline section of the Config module.\n"
                 . "If these configurations are not present, ensure you have run "
                 . "all the patches coming with the LORIS release you are using.\n";
    exit $NeuroDB::ExitCodes::SELECT_FAILURE;
}



## get environment variables

my ($tmp_dir_var, $mni_models, $beastlib) = @ENV{'TMPDIR', 'MNI_MODELS', 'BEASTLIB'};
unless ($mni_models && $beastlib && $tmp_dir_var) {
    print STDERR "\n==> ERROR: the environment variables 'TMPDIR', 'MNI_MODELS' and "
                 . "'BEASTLIB' are required to be set for the defacing script to "
                 . "run. Please ensure you updated your environment file with "
                 . "the proper variables and that you source your environment file "
                 . "before running this script.\n";
    exit $NeuroDB::ExitCodes::INVALID_ENVIRONMENT_VAR;
}



## create the tmp directory where the outputs of the deface pipeline will be
# temporarily stored (before insertion in the database)

my $tmp_dir = &tempdir('deface-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);



## get today's date

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
my $today = sprintf( "%4d-%02d-%02d", $year + 1900, $mon + 1, $mday );



## grep the list of MINC files that will need to be defaced

print "\n==> Fetching all FileIDs to deface.\n" if $verbose;
my @session_ids = defined $session_ids ? split(",", $session_ids) : ();

unless ($to_deface) {
    print "\nNo modalities were set to be defaced in the Config module. Ensure"
          . " to select modalities to deface in the Config module under the imaging"
          . " pipeline section (setting called modalities_to_deface. \n\n";
    exit $NeuroDB::ExitCodes::SUCCESS;
}

my %files_hash  = grep_FileIDs_to_deface(\@session_ids, $to_deface);



## Loop through SessionIDs

foreach my $session_id (keys %files_hash) {
    # extract the hash of the list of files to deface for that session ID
    my %session_files = %{ $files_hash{$session_id} };

    # go to the next session ID if no files to deface for that session ID
    next unless (%session_files);

    # grep the CandID and VisitLabel for the dataset
    my ($candID, $visit) = grep_candID_visit_from_SessionID($session_id);

    # verify that the files are not already defaced
    my ($already_defaced) = check_if_deface_files_already_in_db(
        \%session_files, $session_id
    );
    if ($already_defaced) {
        print STDERR "\n==> WARNING: The files for SessionID $session_id have "
                     . "already been defaced and registered in LORIS. Skipping "
                     . "defacing for this session.\n";
        next;
    }

    # grep the t1 file of reference for the defacing (first FileID for t1 scan type)
    my (%ref_file) = grep_t1_ref_file(\%session_files, $ref_scan_type);

    # determine where the result of the deface command will go
    my ($output_basedir, $output_basename) = determine_output_dir_and_basename(
        $tmp_dir, $candID, $visit, \%ref_file
    );

    # run the deface command
    my (%defaced_images) = deface_session(
        \%ref_file, \%session_files, $output_basename
    );

    # registers the output of the defacing script
    register_defaced_files(\%defaced_images);
}


exit $NeuroDB::ExitCodes::SUCCESS;



=pod

=head3 grep_FileIDs_to_deface($session_id_arr, $modalities_to_deface_arr)

Queries the database for the list of acquisitions' FileID to be used to run the
defacing algorithm based on the provided list of SessionID and Scan_type to
restrict the search.

INPUTS:
  - $session_id_arr          : array of SessionIDs to use when grepping FileIDs
  - $modalities_to_deface_arr: array of Scan_type to use when grepping FileIDs

RETURNS: hash of matching FileIDs to be used to run the defacing algorithm
         organized in a hash as follows:


    {0123}                          # sessionID key
        {flair}                     # flair scan type key
            {$FileID} = $File_path  # key = FileID; value = MINC file path
        {t1}                        # t1 scan type key
            {$FileID} = $File_path  # key = FileID 1; value = MINC file 1 path
            {$FileID} = $File_path  # key = FileID 2; value = MINC file 2 path


=cut

sub grep_FileIDs_to_deface {
    my ($session_id_arr, $modalities_to_deface_arr) = @_;

    # separate the special modalities specified in %SPECIAL_ACQUISITIONS from the
    # standard scan types
    my @special_scan_types = keys %SPECIAL_ACQUISITIONS_FILTER;
    my @special_cases;
    foreach my $special (@special_scan_types) {
        # push the special modalities to a new array @special_cases
        push @special_cases, grep(/$special/, @$modalities_to_deface_arr);
        # remove the special modalities from the modalities array as they will be
        # dealt with differently than standard modalities
        @$modalities_to_deface_arr = grep(! /$special/, @$modalities_to_deface_arr);
    }

    # base query
    my $query = "SELECT  SessionID, FileID, Scan_type, File "
                . "FROM  files f "
                . "JOIN  mri_scan_type mst ON (f.AcquisitionProtocolID = mst.ID) "
                . "JOIN  parameter_file pf USING (FileID) "
                . "JOIN  parameter_type pt USING (ParameterTypeID) "
                . "WHERE pt.Name='acquisition:image_type' AND ( ";

    # add where clause for the different standard scan types to deface
    my @where;
    if (@$modalities_to_deface_arr) {
        @where = map { "mst.Scan_type = ?" } @$modalities_to_deface_arr;
        $query   .= sprintf(" %s ", join(" OR ", @where));
    }

    # add where clause for the different non-standard scan types to deface
    # where we will restrict the images to be defaced to the ones with a face based
    # on parameter_type 'acquisition:image_type'
    if (@special_cases) {
        @where  = map { "(mst.Scan_type = ? AND pf.Value LIKE ?)" } @special_cases;
        $query .= sprintf(" OR %s ", join(" OR ", @where));
    }
    $query .= ")";  # closing the brackets of the modalities WHERE part of the query

    # add where clause for the session IDs specified to the script if -sessionIDs
    # was set
    if ($session_id_arr) {
        @where  = map { "f.SessionID = ?" } @$session_id_arr;
        $query .= sprintf(" AND (%s) ", join(" OR ", @where));
    }

    my $sth = $dbh->prepare($query);

    # create array of parameters
    my @bind_param = @$modalities_to_deface_arr;
    foreach my $special_scan_type (@special_cases) {
        push @bind_param, $special_scan_type;
        push @bind_param, $SPECIAL_ACQUISITIONS_FILTER{$special_scan_type};
    }
    push @bind_param, @$session_id_arr;

    # execute the query
    $sth->execute(@bind_param);

    # grep the list of FileIDs on which to run defacing
    my %file_id_hash;
    while (my $row = $sth->fetchrow_hashref){
        my $session_key   = $row->{'SessionID'};
        my $scan_type_key = $row->{'Scan_type'};
        my $file_id_value = $row->{'FileID'};
        my $file_value    = $row->{'File'};
        $file_id_hash{$session_key}{$scan_type_key}{$file_id_value} = $file_value;
    }

    return %file_id_hash
}


=pod

=head3 grep_candID_visit_from_SessionID($session_id)

Greps the candidate's C<CandID> and the visit label corresponding to the
C<SessionID> given as input.

INPUT: the session ID to use to look for C<CandID> and visit label

RETURNS: the candidate's C<CandID> and the session visit label

=cut

sub grep_candID_visit_from_SessionID {
    my ($session_id) = @_;

    my $query  = "SELECT CandID, Visit_label FROM session WHERE ID = ?";
    my $result = $dbh->selectrow_hashref($query, undef, $session_id);

    my $cand_id     = $result->{'CandID'     };
    my $visit_label = $result->{'Visit_label'};

    return $cand_id, $visit_label;
}


=pod

=head3 check_if_deface_files_already_in_db($session_files, $session_id)

Checks whether there are already defaced images present in the database for
the session.

INPUTS:
  - $session_files: list of files to deface
  - $session_id   : the session ID to use to look for defaced images in C<files>

RETURNS: 1 if there are defaced images found, 0 otherwise

=cut

sub check_if_deface_files_already_in_db {
    my ($session_files, $session_id) = @_;

    my @defaced_scan_types = map { $_ . '-defaced' } keys $session_files;

    # base query
    my $query = "SELECT COUNT(*) "
                 . " FROM files f "
                 . " JOIN mri_scan_type mst ON (mst.ID=f.AcquisitionProtocolID) ";

    # add where clause for the different defaced scan types
    my @where = map { "mst.Scan_type = ?" } @defaced_scan_types;
    $query   .= sprintf(" WHERE (%s) ", join(" OR ", @where));
    $query   .= " AND SessionID = ?";

    # prepare and execute the query
    my $sth   = $dbh->prepare($query);
    $sth->execute(@defaced_scan_types, $session_id);

    # grep the results
    my ($count) = $sth->fetchrow_array;

    return $count ? 1 : 0;
}

=pod

=head3 grep_t1_ref_file($session_files, $ref_t1_scan_type)

Grep the first t1w image from C<$session_files> to use it as a reference image for
C<deface_minipipe.pl>.

INPUTS:
  - $session_files   : list of files to deface
  - $ref_t1_scan_type: LORIS scan type of the t1w file to use as a reference
                       for C<deface_minipipe.pl>

RETURNS: hash with information for the reference t1w image

=cut

sub grep_t1_ref_file {
    my ($session_files, $ref_t1_scan_type) = @_;

    # grep the first t1w image to use as a reference when executing deface_minipipe.pl
    my %t1_files   = %{ $$session_files{$ref_t1_scan_type} };
    my @t1_fileIDs = sort( grep( defined $t1_files{$_}, keys %t1_files ) );
    my %ref_file   = (
        "FileID"    => $t1_fileIDs[0],
        "File"      => $t1_files{$t1_fileIDs[0]},
        "Scan_type" => $ref_t1_scan_type
    );

    # remove that reference file from the hash of other files to deface
    delete $$session_files{$ref_t1_scan_type}{$t1_fileIDs[0]};

    return %ref_file;
}


=pod

=head3 determine_output_dir_and_basename($root_dir, $candID, $visit, $ref_file)

Determine the output directory path and basename to be used by C<deface_minipipe.pl>.

INPUTS:
  - $root_dir: root directory (usually a temporary directory where defaced outputs
               will be created)
  - $candID  : candidate's C<CandID>
  - $visit   : candidate's visit label
  - $ref_file: hash with information about the reference t1 file to use to deface

RETURNS:
  - $output_basedir : output base C<CandID/VisitLabel> directory where defaced images
                      will be created
  - $output_basename: basename to be used to create the C<_deface_grid_0.mnc> file

=cut

sub determine_output_dir_and_basename {
    my ($root_dir, $candID, $visit, $ref_file) = @_;

    # determine output base directory and create it if it does not exist yet
    my $output_basedir  = "$root_dir/$candID/$visit/";
    unless (-e $output_basedir) {
        make_path($output_basedir)
            or die "Could not create directory $output_basedir: $!";
    }

    # determine the output base name for the *_deface_grid_0.mnc output
    my $output_basename = $output_basedir . basename($$ref_file{File});
    $output_basename    =~ s/_$$ref_file{Scan_type}_\d\d\d\.mnc//i;

    # return the output base directory and output basename
    return $output_basedir, $output_basename;
}


=pod

=head3 deface_session($ref_file, $session_files, $output_basename)

Function that will run C<deface_minipipe.pl> on all anatomical images of the session
and will return all defaced outputs in a hash.

INPUTS:
  - $ref_file       : hash with info about the reference t1w file used to deface
  - $session_files  : list of other files than the reference t1w file to deface
  - $output_basename: output basename to be used by C<deface_minipipe.pl>

RETURNS: hash of defaced images with relevant information necessary to register them

=cut

sub deface_session {
    my ($ref_file, $session_files, $output_basename) = @_;

    # initialize the command with the t1 reference file
    my $cmd = "deface_minipipe.pl $data_dir/$$ref_file{File} ";

    # add multi-constrast modalities to cmd line & remove them from $session_files
    foreach my $multi (@MULTI_CONTRAST_ACQUISITIONS_BASE_NAMES) {
        my @scan_types         = keys $session_files;
        my @matching_types     = grep (/$multi/i, @scan_types);
        my @non_matching_types = grep (!/$multi/i, @scan_types);
        my (@multi_files_list, @other_files);
        foreach my $match (@matching_types) {
            # for each multi-contrast modality found, grep the file path
            my %files   = %{ $$session_files{$match} };
            push(@multi_files_list, map { "$data_dir/$files{$_}" } keys %files);
        }
        foreach my $non_match (@non_matching_types) {
            my %files = %{ $$session_files{$non_match} };
            push(@other_files, map { "$data_dir/$files{$_}" } keys %files);
        }
        $cmd .= " " . join(",", @multi_files_list) if @multi_files_list;
        $cmd .= " " . join(" ", @other_files)      if @other_files;
    }

    # then finalize the command with the output basename and additional options
    $cmd .= " $output_basename --keep-real-range --beastlib $beastlib "
        . " --model mni_icbm152_t1_tal_nlin_sym_09c "
        . " --model-dir $mni_models";

    my $exit_code = system($cmd);
    if ($exit_code != 0) {
        print "\nAn error occurred when running deface_minipipe.pl. Exiting now\n\n";
        exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
    }

    my %defaced_images = fetch_defaced_files(
        $ref_file, $session_files, $output_basename
    );

    return %defaced_images;
}


=pod

=head3 fetch_defaced_files($ref_file, $session_files, $output_basename)

Function that will determine the name of the defaced outputs and check that the
defaced outputs indeed exists in the file system. If all files are found in the
filesystem, it will return a hash with all information necessary for registration
of the defaced image.

INPUTS:
  - $ref_file       : hash with info about the reference t1w file used to deface
  - $session_files  : list of other files than the reference t1w file to deface
  - $output_basename: output basename to be used by C<deface_minipipe.pl>

RETURNS: hash of defaced images with relevant information necessary to register them

=cut

sub fetch_defaced_files {
    my ($ref_file, $session_files, $output_basename) = @_;

    my $deface_dir = dirname($output_basename);
    my $deface_ref = $deface_dir . '/' . basename($$ref_file{File});
    $deface_ref    =~ s/\.mnc$/_defaced\.mnc/;

    # create a hash with all information about the defaced images and add the
    # reference t1 defaced image to it
    my %defaced_images;
    # append the reference t1 defaced image to the hash
    $defaced_images{$deface_ref}{InputFileID} = $$ref_file{FileID};
    $defaced_images{$deface_ref}{Scan_type}   = $$ref_file{Scan_type};

    # for each files in $session_files, append the defaced images to the hash
    foreach my $scan_type (keys $session_files) {
        my %files = %{ $$session_files{$scan_type} };
        foreach my $fileID (keys %files) {
            my $deface_file   = $deface_dir . '/' . basename($files{$fileID});
            $deface_file      =~ s/\.mnc$/_defaced\.mnc/;
            $defaced_images{$deface_file}{InputFileID} = $fileID;
            $defaced_images{$deface_file}{Scan_type}    = $scan_type;
        }
    }

    # ensure all the files can be found on the filesystem
    foreach my $file (keys %defaced_images) {
        return undef unless (-e $file);
    }

    return %defaced_images;
}


=pod

=head3 register_defaced_files($defaced_images)

Registers the defaced images using C<register_processed_data.pl>.

INPUT: hash with the defaced images storing their input FileID and scan type

=cut

sub register_defaced_files {
    my ($defaced_images) = @_;

    my $register_cmd = "register_processed_data.pl "
                       . " -profile $profile "
                       . " -sourcePipeline MINC_deface "
                       . " -tool 'uploadNeuroDB/bin/deface_minipipe.pl' "
                       . " -pipelineDate $today "
                       . " -coordinateSpace native "
                       . " -outputType defaced ";

    foreach my $file (keys $defaced_images) {
        my $input_fileID = $$defaced_images{$file}{InputFileID};
        my $scan_type    = $$defaced_images{$file}{Scan_type} . "-defaced";

        # verify that the scan type exists in mri_scan_type, if not create it
        create_defaced_scan_type($scan_type);

        # append file, scan type, sourceFileID & inputFileIDs to the command
        $register_cmd .= " -inputFileIDs $input_fileID "
                         . " -sourceFileID $input_fileID"
                         . " -scanType $scan_type "
                         . " -file $file";

        # register the scan in the DB
        my $exit_code = system($register_cmd);
        if ($exit_code != 0) {
            print "\nAn error occurred when running register_processed_data.pl."
                  . " Error Code was: " . $exit_code >> 8 . "Exiting now\n\n";
            exit $NeuroDB::ExitCodes::PROGRAM_EXECUTION_FAILURE;
        }
    }
}


=pod

=head3 create_defaced_scan_type($scan_type)

Function that inserts a new scan type in C<mri_scan_type> if the scan type does not
already exists in C<mri_scan_type>.

INPUT: the scan type to look for or insert in the C<mri_scan_type> table

=cut

sub create_defaced_scan_type {
    my ($scan_type) = @_;

    my $select     = "SELECT COUNT(*) FROM mri_scan_type WHERE Scan_type = ?";
    my $select_sth = $dbh->prepare($select);
    $select_sth->execute($scan_type);

    my ($count) = $select_sth->fetchrow_array;
    unless ($count) {
        my $insert = "INSERT INTO mri_scan_type SET Scan_type = ?";
        my $sth    = $dbh->prepare($insert);
        $sth->execute($scan_type);
    }
}



=pod


=head1 LICENSING

License: GPLv3


=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience


=cut