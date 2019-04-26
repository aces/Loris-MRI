package DICOM::DCMSUM;

=pod

=head1 NAME

DICOM::DCMSUM -- Archives DICOM summaries

=head1 SYNOPSIS

=head1 DESCRIPTION

Deals with DICOM summaries for archiving and other purposes.

=head2 Methods

=cut

use strict;
# some general stuff
use File::Basename;
use File::Find;
use Math::Round;
use Digest::MD5;

# more specific stuff
use DICOM::DICOM;
use NeuroDB::ExitCodes;



=pod

=head3 new($dcm_dir, $tmp_dir) >> (constructor)

Creates a new instance of this class.

INPUTS:
  - $dcm_dir: DICOM directory
  - $tmp_dir: target location

RETURNS: a C<DICOM::DCMSUM> object

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless ($self, $class);

    my $dcm_dir = shift;
    my $tmp_dir = shift;

# summary Type VERSION: This should be changed, if - and only if the way the summary is created changes!!
    $self->{sumTypeVersion} = 1;

# set up some basic stuff    
    $self->{dcmdir}     = $dcm_dir;                    # the dcm source dir
    $self->{tmpdir}     = $tmp_dir;                    # tmp dir 
    $self->{metaname}   = basename($self->{dcmdir});   # the name for the .meta file
    
    $self->{archivedir} = undef;
# get an array describing ALL files
    $self->{dcminfo}   = [$self->content_list($self->{dcmdir})]; 
### make sure that there is at least one dicom file in target directory
    $self->{dcmcount}          = $self->dcm_count();  
# studyuid if there is only one study in source
    $self->{studyuid}   = $self->confirm_single_study($self->{dcminfo});
 
# getting an idea on what there is and breaking it down to different acquisitions
    $self->{acqu_AoH}   = [ $self->acquisition_AoH($self->{dcminfo}) ];  # Array of Hashes decsribing acquisition parameters for each file
    $self->{acqu_Sum}   = { $self->collapse($self->{acqu_AoH}) };        # hash table acquisition summary collapsed by unique acquisition definitions
    $self->{acqu_List}  = [ $self->acquisitions($self->{acqu_Sum}) ];    # acquisition Listing sorted by acquisition number to be used for summary

# hash table containing all kind of patient and institution info
    $self->{header}     = {}; 
    $self->{header}     = $self->fill_header($self->{dcminfo});
    
# some more counts 
    $self->{totalcount}        = $self->file_count();
    $self->{nondcmcount}       = $self->{totalcount} - $self->{dcmcount};
    $self->{acquisition_count} = $self->acquistion_count();  
    $self->{user}              = $ENV{'USER'};

    return $self;
}

=pod 

=head3 database($dbh, $meta, $update, $tarType, $tarLog, $DCMmd5, $Archivemd5, $Archive, $neurodbCenterName)

Inserts or updates the C<tarchive> tables.

INPUTS:
  - $dbh              : database handle
  - $meta             : name of the .meta file
  - $update           : set to 1 to update C<tarchive> entry, 0 otherwise
  - $tarType          : tar type version
  - $tarLog           : name of the .log file
  - $DCMmd5           : DICOM MD5SUM
  - $Archivemd5       : DICOM archive MD5 sum
  - $Archive          : archive location
  - $neurodbCenterName: center name

RETURNS: 1 on success

=cut

sub database {
    my $self   = shift;
    my $dbh    = shift;
    my $meta   = shift;
    my $update = shift;
    
    # these are only available if you run dicomTar
    my $tarType     = shift;
    my $tarLog      = shift;
    my $DCMmd5      = shift;
    my $Archivemd5  = shift;
    my $Archive     = shift;
    my $neurodbCenterName = shift;

    if(defined($neurodbCenterName)) {
        $neurodbCenterName = "'$neurodbCenterName'";
    } else {
        $neurodbCenterName = "NULL";
    }

    # whether the query worked fine
    my $success = undef;
    # check if this StudyUID is already in your database
    my ($unique_study, $message) = $self->is_study_unique($dbh, $update, $Archivemd5);
    if (!$unique_study && !$update) {
        # if the study is not unique and update is not set it means the script
        # should stop running and display the error message
        print STDERR $message;
        exit $NeuroDB::ExitCodes::FILE_NOT_UNIQUE;
    }
    # the tarchive is unique so set update to false since it will need an insert
    $update = 0 if $unique_study;


    # INSERT or UPDATE 
    # get acquisition metadata
    my $sfile = "$self->{tmpdir}/$meta.meta";
    my $metacontent = &read_file($sfile);
    
    (my $common_query_part = <<QUERY) =~ s/\n/ /gm;  
      tarchive SET  
        DicomArchiveID = ?,       PatientName = ?,
        PatientID = ?,            PatientDoB = ?,
        PatientSex = ?,           DateAcquired = ?,
        ScannerManufacturer = ?,  ScannerModel = ?,
        ScannerSerialNumber = ?,  ScannerSoftwareVersion = ?,
        CenterName = ?,           AcquisitionCount = ?,
        NonDicomFileCount = ?,    DicomFileCount = ?,
        CreatingUser = ?,         SourceLocation = ?,
        sumTypeVersion = ?,       AcquisitionMetadata = ?,
        DateLastArchived = NOW()
QUERY

    #-----------------------------------------------------------
    # Try to determine the creating user for the tarchive row
    # to be inserted. This is done by finding the row in 
    # the mri_upload table with the DecompressedLocation equal
    # to the $self->{dcmdir}. This is only done when the MRI
    # pipeline is run in auto launch mode: the creating user is
    # set to $ENV{'user'} otherwise (note that when the auto
    # launch is turned on, $ENV{'USER'} will be '').
    #-----------------------------------------------------------
    my $creating_user = $self->{user};

    # If we are in auto launch mode
    if(length($creating_user) == 0) {
        (my $query = <<QUERY) =~ s/\n/ /gm;
          SELECT UploadedBy
          FROM mri_upload
          WHERE DecompressedLocation = ?
QUERY
        # Lookup in the mri_upload table
        my $sth     = $dbh->prepare($query);
        my @args = ($self->{dcmdir});
        $success = $sth->execute(@args);
        print "Failed running query: $query\n\n\n" unless $success;

        # Fetch result
        my @row = $sth->fetchrow_array();
        if(@row == 0) {
            print "No row in mri_upload table with DecompressedLocation = " . $self->{dcmdir} . "\n";
            $creating_user = undef;
        } elsif(@row > 1) {
            print "More than one row in mri_upload table with DecompressedLocation = " . $self->{dcmdir} . "\n";
            $creating_user = undef;
        } else {
            $creating_user = $row[0];
        }
    }

    # If DoB is not set, $self->{header}->{birthdate} = '' which will
    # not be allowed anymore in MySQL 5.7 for date fields 
    $self->{header}->{birthdate} = undef if ($self->{header}->{birthdate} eq '');
    $self->{header}->{scandate}  = undef if ($self->{header}->{scandate} eq '');

    my @values = 
      (
       $self->{studyuid},                 $self->{header}->{pname},           
       $self->{header}->{pid},            $self->{header}->{birthdate},      
       $self->{header}->{sex},            $self->{header}->{scandate},       
       $self->{header}->{manufacturer},   $self->{header}->{scanner},          
       $self->{header}->{scanner_serial}, $self->{header}->{software},      
       $self->{header}->{institution},    $self->{acquisition_count},          
       $self->{nondcmcount},              $self->{dcmcount},                  
       $creating_user,                    $self->{dcmdir},                     
       $self->{sumTypeVersion},           $metacontent   
      );
    
    # this only applies if you are archiving your data
    if ($Archivemd5) { 
       ($common_query_part = <<QUERY) =~ s/\n/ /gm; 
          $common_query_part,  tarTypeVersion = ?,  
          md5sumArchive = ?,   md5sumDicomOnly = ?,  
          ArchiveLocation = ?, CreateInfo = ? 
QUERY
        my @new_vals = 
          (
           $tarType, $Archivemd5, 
           $DCMmd5,  $Archive, 
           $tarLog
          );
        push(@values, @new_vals);
    }

    my $query;
    if (!$update) { 
        ($query = <<QUERY) =~ s/\n/ /gm;
          INSERT INTO 
            $common_query_part, 
            DateFirstArchived = NOW(), 
            neurodbCenterName = ?
QUERY
        push(@values, $neurodbCenterName);
    } 
    else {  
        ($query = <<QUERY) =~ s/\n/ /gm;
          UPDATE 
            $common_query_part 
          WHERE DicomArchiveID = ? 
QUERY
        push(@values, $self->{studyuid});
    }
    
    my $sth  = $dbh->prepare($query);
    $success = $sth->execute(@values);
#FIXME
print "Failed running query: $query\n\n\n" unless $success;

    # now get the TarchiveID
    my $tarchiveID;
    if(!$update) {
        $tarchiveID = $dbh->{'mysql_insertid'};
    } else {
        ($query = <<QUERY) =~ s/\n/ /gm;
          SELECT 
            TarchiveID 
          FROM 
            tarchive 
          WHERE 
            DicomArchiveID = ? 
            AND SourceLocation= ?
QUERY
        $sth = $dbh->prepare($query);
        $sth->execute($self->{studyuid}, $self->{dcmdir});
        my @row = $sth->fetchrow_array();
        $tarchiveID = $row[0];
    }
    
    # if update, nuke series and files records then reinsert them
    if($update) {
        (my $delete_series = <<QUERY) =~ s/\n/ /gm;
          DELETE FROM 
            tarchive_series 
          WHERE 
            TarchiveID = ?
QUERY
        (my $delete_files = <<QUERY) =~ s/\n/ /gm;
          DELETE FROM 
            tarchive_files 
          WHERE 
            TarchiveID = ?
QUERY
        my $sth_series = $dbh->prepare($delete_series);
        my $sth_files  = $dbh->prepare($delete_files);
        # Deleting from tarchive_files first because of db constraints.
        $sth_files->execute($tarchiveID);
        $sth_series->execute($tarchiveID);
    }

    # now create the tarchive_series records
    ($query = <<QUERY) =~ s/\n/ /gm;
      INSERT INTO 
        tarchive_series 
          (
           TarchiveID,    SeriesNumber,   SeriesDescription, 
           SequenceName,  EchoTime,       RepetitionTime, 
           InversionTime, SliceThickness, PhaseEncoding, 
           NumberOfFiles, SeriesUID,      Modality
          ) 
        VALUES 
          (
           ?,             ?,              ?, 
           ?,             ?,              ?, 
           ?,             ?,              ?, 
           ?,             ?,              ?
          )
QUERY
    my $insert_series = $dbh->prepare($query);
    foreach my $acq (@{$self->{acqu_List}}) {

        # insert the series
        my ($seriesNum, $sequName,  $echoT, $repT, $invT, $seriesName, $sl_thickness, $phaseEncode, $seriesUID, $modality, $num) = split(':::', $acq);
        
        #InversionTime may not be insert in the DICOM Header under certain sequences acquisitions  
        if ($invT eq '') {
            $invT = undef;
        }
        if ($seriesName =~ /ColFA$/i) {
            $echoT        = undef;    
            $repT         = undef;
            $sl_thickness = undef;
        }
        if ($modality eq 'MR') {
            my @values = 
              (
               $tarchiveID, $seriesNum,    $seriesName, 
               $sequName,   $echoT,        $repT, 
               $invT,       $sl_thickness, $phaseEncode, 
               $num,        $seriesUID,    $modality
              );
            $insert_series->execute(@values);
        } elsif ($modality eq 'PT') {
            my @values = 
              (
               $tarchiveID, $seriesNum,    $seriesName, 
               undef,       undef,         undef, 
               undef,       $sl_thickness, undef, 
               $num,        $seriesUID,    $modality
              );
            $insert_series->execute(@values);
        }
    }

    # now create the tarchive_files records
    (my $insert_query = <<QUERY) =~ s/\n/ /gm;
      INSERT INTO 
        tarchive_files 
          (
           TarchiveID, SeriesNumber,      FileNumber, 
           EchoNumber, SeriesDescription, Md5Sum, 
           FileName,   TarchiveSeriesID
          ) 
        VALUES 
          (
           ?,          ?,                 ?, 
           ?,          ?,                 ?, 
           ?,          ?
          )
QUERY
    my $query_select_TarchiveSeriesID = "SELECT TarchiveSeriesID FROM tarchive_series WHERE SeriesUID = ? AND EchoTime = ?";
    my $select_TarchiveSeriesID = $dbh->prepare($query_select_TarchiveSeriesID);
    my $insert_file = $dbh->prepare($insert_query);
    my $dcmdirRoot = dirname($self->{dcmdir});
    foreach my $file (@{$self->{'dcminfo'}}) {
        # insert the file
        my $filename = $file->[4];
        $filename =~ s/^${dcmdirRoot}\///;
        $file->[2] = undef if($file->[2] eq '');
        $select_TarchiveSeriesID->execute($file->[24], $file->[6]); # based on SeriesUID and EchoTime
        my ($TarchiveSeriesID) = $select_TarchiveSeriesID->fetchrow_array();
        my @values;
        if($file->[21] && $file->[25] eq 'MR') { # file is dicom and an MRI scan
            @values = 
              (
               $tarchiveID, $file->[1],  $file->[3], 
               $file->[2],  $file->[12], $file->[20], 
               $filename,   $TarchiveSeriesID
              );
        } elsif($file->[21] && $file->[25] eq 'PT') { # file is dicom and a PET scan
            @values = 
              (
               $tarchiveID, $file->[1],  $file->[3], 
               undef,       $file->[12], $file->[20], 
               $filename,   $TarchiveSeriesID
              );
        } else {
            @values = 
              (
               $tarchiveID, undef, undef, 
               undef,       undef, $file->[20], 
               $filename,   $TarchiveSeriesID
              );
        }
        $insert_file->execute(@values);
    }
    return $success; # if query worked this will return 1;
}

=pod

=head3 is_study_unique($dbh, $update, $Archivemd5)

Verifies if the DICOM study is already registered in the C<tarchive> table
using the C<StudyUID> field of the DICOM files. If the study is already present in the
C<tarchive> tables but C<-clobber> was not when running C<dicomTar.pl> or that we are
using C<dicomSummary.pl>, it will return the appropriate error message.

INPUTS:
  - $dbh       : database handle
  - $update    : set to 1 to update C<tarchive> entry, 0 otherwise
  - $Archivemd5: DICOM archive MD5 sum

RETURNS:
  - $unique_study: set to 0 if the study was found in the database, 1 otherwise
  - $message     : error message or undef if no error found


=cut

sub is_study_unique {
    my ($self, $dbh, $update, $Archivemd5) = @_;

    # check if this StudyUID is already in your database
    (my $query = <<QUERY) =~ s/\n/ /gm;
      SELECT
        DicomArchiveID,
        CreateInfo,
        LastUpdate,
        CreatingUser,
        md5sumArchive
      FROM
        tarchive
      WHERE
        DicomArchiveID=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($self->{studyuid});

    # if there is an entry get create info
    my ($message, $unique_study);
    if($sth->rows > 0) {
        $unique_study = 0;
        my @row = $sth->fetchrow_array();
        if ($update == 0) {
            $message = <<MESSAGE;

PROBLEM:
The user '$row[3]' has already inserted this study.
The unique study ID is '$row[0]'.
This is the information retained from the first time the study was inserted:
$row[1]

Last update of record:
$row[2]

MESSAGE
        } elsif (!$Archivemd5 && $row[3] ne "") {
            # do not allow to run dicomSummary with database option if the study has already been archived
            $message = <<MESSAGE;

PROBLEM: This study has already been archived. You can only re-archive it using dicomTar!
This is the information retained from the first time the study has been archived:
$row[1]

MESSAGE
        }
    } else {
        $unique_study = 1;
    }

    return $unique_study, $message;
}


=pod 

=head3 read_file($file)

Reads the content of a file (typically .meta file in the DICOM archive).

INPUT: the file to be read

RETURNS: the content of the file

=cut

sub read_file {
    my $file = shift;
    my $content;
    open CONTENT, "$file";
    while ( <CONTENT> ) {
	$content = $content . $_;
    }
    close CONTENT;
    return $content;
}


=pod

=head3 acquistion_count()

Figures out the total number of acquisitions.

RETURNS: number of acquisitions

=cut

sub acquistion_count {
    my ($self) = shift;
    my @ac = @{$self->{acqu_List}};
    my $count = @ac;
    return $count;
}


=pod

=head3 file_count()

Figures out the total number of files.

RETURNS: number of files

=cut

sub file_count {
    my ($self) = shift;
    my @ac = @{$self->{dcminfo}};
    my $count = @ac;
    return $count;
}


=pod

=head3 dcm_count()

Figures out the total number of DICOM files.

RETURNS: number of DICOM files, or exits if no DICOM file found.

=cut

sub dcm_count {
    my ($self) = shift;
    my @ac = @{$self->{dcminfo}};
    my $count = 0;
    foreach my $file (@ac) {
	if($file->[21]) { # file is dicom
	    $count++;
	}
    }
    if ($count == 0) {
	print "\n\t The target directory does not contain a single DICOM file. \n\n\n";
	    exit $NeuroDB::ExitCodes::MISSING_FILES;
    }
    else { return $count;}
}


=pod 

=head3 acquisition_AoH($self->{dcminfo})

Creates an Array of Hashes (AoH) describing acquisition parameters for each
file.

INPUT: list of DICOM files

RETURNS: array of hashes with acquisition parameters for each file

=cut

sub acquisition_AoH {
    my $self = shift;
    my @AoH = ();
    my $i = 0;
    # Generate an array of hashes.
    foreach my $info ( @{$self->{dcminfo}} ) {
	    # create an array of hashes. Containing the protocol info for every file 
	    if(@{$info}[21]) {
	        $AoH[$i]  = { 
                'seriesNum'     => @{$info}[1], 
                'seriesName'    => @{$info}[12], 
                'sl_thickness'  => @{$info}[18], 
                'seriesUID'     => @{$info}[24],
                'modality'      => @{$info}[25]
	        };
            if(@{$info}[25] eq "MR") {
                $AoH[$i]->{'sequName'}    = @{$info}[17], 
                $AoH[$i]->{'echoN'}       = @{$info}[2],
                $AoH[$i]->{'echoT'}       = @{$info}[6], 
                $AoH[$i]->{'invT'}        = @{$info}[7], 
                $AoH[$i]->{'repT'}        = @{$info}[5],
                $AoH[$i]->{'phaseEncode'} = @{$info}[19]
            } elsif (@{$info}[25] eq "PT") {
                # Add parameters specific to PET here
            }
	        $i++;
	    }
    }
    return @AoH; # meaning array of hashes
} 


=pod 

=head3 collapse($self->{acqu_AoH})

Collapses the AoH to get a summary of acquisitions.

INPUT: array of hashes with acquisition parameters for each DICOM file

RETURNS: hash table acquisition summary collapsed by unique acquisition
definitions

=cut

sub collapse {
    my $self = shift;
    my %hash;
    my $prev = 0;
    my $i = 0;
    # go through array and get rid of duplicate elements
    foreach my $value ( @{$self->{acqu_AoH}} ) {
	    # this should be the same for series that follow the dicom specs
        my $common = join(':::', ($value->{'sequName'},     $value->{'seriesNum'}, 
                                  $value->{'echoN'} 
                                 )
                         );
        my $now    = join(':::', ($value->{'seriesNum'},    $value->{'sequName'},  
                                  $value->{'echoT'},        $value->{'repT'},      
                                  $value->{'invT'},         $value->{'seriesName'}, 
                                  $value->{'sl_thickness'}, $value->{'phaseEncode'}, 
                                  $value->{'seriesUID'},    $value->{'modality'}
                                 )
                         );
	    $i = 0 if ($now ne $prev);
	    $i++;
	    $hash{$common} = join(':::', $now, $i);
	    $prev = $now;
    } # end of foreach 
    # what we really want
    return %hash;
} # end of function


=pod 

=head3 acquisitions(self->{acqu_Sum})

Sorts the Array of Hash by acquisition number.

INPUT: array of hash table acquisition summary

RETURNS: acquisition listing sorted by acquisition number to be used for summary

=cut

sub acquisitions {
    my $self  = shift;
    my @retarr= ();
    foreach my $key (sort keys( %{$self->{acqu_Sum}} )) {
        push @retarr, $self->{acqu_Sum}->{$key};
    }
    # sort the bloody array by Acquisition numbers
    # fixme has to be changed some day to actually sort by the first
    # value which is the acquistion number. Will allow you to use perl -w
    @retarr = sort {$a <=> $b} (@retarr);
    return @retarr;
    
} # end of function


=pod 

=head3 content_list($dcmdir)

Gets DICOM info from all files in a directory.

Note: The -k5 was added on August 28th 2006 because the guys in Kupio assign
duplicate FN SN EN values for scouts and subsequent scans.

INPUT: DICOM directory

RETURNS: sorted DICOM information from all the files in the DICOM directory

=cut

sub content_list {
    my ($self, $dcmdir) = @_;
    my @info = (); 
    my $find_handler = sub { if(-f $File::Find::name) { push @info, &read_dicom_data($File::Find::name); } };
    find($find_handler, $dcmdir);
    my @sorted_info = sort { ($b->[21] <=>  $a->[21])
			  || ($a->[1]  <=>  $b->[1])
			  || ($a->[5]  <=>  $b->[5])
			  || ($a->[17] cmp  $b->[17])
			  || ($a->[2]  <=>  $b->[2])
			  || ($a->[3]  <=>  $b->[3])
			    } @info;
    
    return @sorted_info;
}


=pod

=head3 read_dicom_data($file)

Gets DICOM info from a DICOM file.

INPUT: DICOM file to read

RETURNS: array with pertinent DICOM information read from the DICOM file

=cut

sub read_dicom_data {
    my $file = shift;

    # read the file, assuming it is dicom
    my $dicom = DICOM->new();
    my $fileIsDicom = ! ($dicom->fill($file));
    
    #my $dicomTest          = trimwhitespace($dicom->value('0020','0032'));  # a basic test to exclude stupid pseudo dicom files
    my $studyUID           = trimwhitespace($dicom->value('0020','000D'));  # element 0 0 is study uid
    if($studyUID eq '') {$fileIsDicom = 0;}                              # element 0 21 is whether file is Dicom or not

    my ($series,          $echo,           $image,              $tr,    
        $te,              $ti,             $date,               $pname, 
        $pdob,            $pid,            $series_description, $sex,
        $scanner,         $software,       $institution,        $sequence,       
        $slice_thickness, $phase_encoding, $manufacturer,       $scanner_serial, 
        $seriesUID,       $modality
       );

    # see if the file was really dicom
    if($fileIsDicom) {
	$studyUID           = trimwhitespace($dicom->value('0020','000D'));  # element 0 0 is study uid
	$series             = trimwhitespace($dicom->value('0020','0011'));  # element 0 1 is series
	$echo               = trimwhitespace($dicom->value('0018','0086'));  # element 0 2 is echo number
	$image              = trimwhitespace($dicom->value('0020','0013'));  # element 0 3 is image number
	                                                                     # element 0 4 is the file itself  
	$tr                 = trimwhitespace($dicom->value('0018','0080'));  # element 0 5 is repetition time  
	$te                 = trimwhitespace($dicom->value('0018','0081'));  # element 0 6 is echo time
	$ti                 = trimwhitespace($dicom->value('0018','0082'));  # element 0 7 is inversion time
	$date               = trimwhitespace($dicom->value('0008','0020'));  # element 0 8 is date of study
	$pname              = trimwhitespace($dicom->value('0010','0010'));  # element 0 9 is patient name
	$pdob               = trimwhitespace($dicom->value('0010','0030'));  # element 0 10 is patitent date of birth 
	$pid                = trimwhitespace($dicom->value('0010','0020'));  # element 0 11 is patient ID
	$series_description = trimwhitespace($dicom->value('0008','103E'));  # element 0 12 is series description
	$sex                = trimwhitespace($dicom->value('0010','0040'));  # element 0 13 -attvalue 0010 0040    patient sex
	$scanner            = trimwhitespace($dicom->value('0008','1090'));  # element 0 14 -attvalue 0008 1090    scanner model
	$software           = trimwhitespace($dicom->value('0018','1020'));  # element 0 15 -attvalue 0018 1020    software version
	$institution        = trimwhitespace($dicom->value('0008','0080'));  # element 0 16 -attvalue 0008 0080    institution
	$sequence           = trimwhitespace($dicom->value('0018','0024'));  # element 0 17 -attvalue  0018 0024   sequence name
	$slice_thickness    = trimwhitespace($dicom->value('0018','0050'));  # element 0 18 slice_thickness
	$phase_encoding     = trimwhitespace($dicom->value('0018','1312'));  # element 0 19 phase encoding

    # these have been added only for tarchiveLoader.pl functionality
    $manufacturer       = trimwhitespace($dicom->value('0008','0070'));  # element 0 22  scanner manufacturer
    $scanner_serial     = trimwhitespace($dicom->value('0018','1000'));  # element 0 23  scanner serial number

	$seriesUID          = trimwhitespace($dicom->value('0020','000E'));  # element 0 24 is series uid
    $modality           = trimwhitespace($dicom->value('0008','0060'));  # element 0 25 is modality (PT=PET, MR=MRI)
    }    
    my @md5bits = split(' ', md5sum($file));                         # element 0 20 md5Sum
    my $md5 = $md5bits[0];

    $te = &Math::Round::nearest(0.01, $te*1) unless (!defined($te) || ($te eq ""));
    $tr = &Math::Round::nearest(0.01, $tr*1) unless (!defined($tr) || ($tr eq ""));
    $ti = &Math::Round::nearest(0.01, $ti*1) unless (!defined($ti) || ($ti eq ""));
    $slice_thickness = &Math::Round::nearest(0.01, $slice_thickness*1) unless (!defined($slice_thickness) || ($slice_thickness eq ""));
    
    return  [ $studyUID,           $series,      $echo,            $image, 
              $file,               $tr,          $te,              $ti,   
              $date,               $pname,       $pdob,            $pid,
              $series_description, $sex,         $scanner,         $software, 
              $institution,        $sequence,    $slice_thickness, $phase_encoding,
              $md5,                $fileIsDicom, $manufacturer,    $scanner_serial,
              $seriesUID,          $modality
            ];

}


=pod 

=head3 fill_header()

Fills header information reading the first valid DICOM file.

RETURNS: header information

=cut

sub fill_header {
    my $self = shift;
    # fixme: this makes it more obvious to access array members
    my @head_info = @{$self->{'dcminfo'}};
    # Loop till you find a valid dicom
    my $i = 0;
    while(! @{$head_info[$i]}[21]) {
	$i++;
    }
    $self->{header}->{pname}       = $head_info[$i]->[9];
    $self->{header}->{pid}         = $head_info[$i]->[11];
    $self->{header}->{birthdate}   = &date_format($head_info[$i]->[ 10]);
    $self->{header}->{scandate}    = &date_format($head_info[$i]->[  8]);
    $self->{header}->{sex}         = $head_info[$i]->[ 13 ];
    $self->{header}->{scanner}     = $head_info[$i]->[ 14 ];
    $self->{header}->{software}    = $head_info[$i]->[ 15 ];
    $self->{header}->{institution} = $head_info[$i]->[ 16 ];
    $self->{header}->{modality}    = $head_info[$i]->[ 25 ];

# these have been added for tarchiveLoader.pl
    $self->{header}->{manufacturer}       = $head_info[$i]->[ 22 ];
    $self->{header}->{scanner_serial}     = $head_info[$i]->[ 23 ];    
    return $self->{header};
}


=pod 

=head3 confirm_single_study()

Confirms that only one DICOM study is in the DICOM directory to be archived.
Returns C<False> if there is more than one C<StudyUID>, otherwise it returns
that C<StudyUID>.

RETURNS: C<StudyUID> found in the DICOM directory, or C<false> if more than one
study was found

=cut

sub confirm_single_study {
    my $self = shift;
    my %hash;
    my $i = 0;
    foreach my $case ( @{$self->{dcminfo}} ) {
		  # only count the file if it is dicom.
		  if ( @$case[21] ) {
		      my $key = @$case[0];
		      $hash{$key} = 1;
		  }
		  $i++;
    }
    if(scalar(keys(%hash)) > 1) { 
	print "\n\t ERROR: This class is designed around the notion of a \'Study\'.\n\t You can't use it with data from multiple studies. \n\nThe following study UIDs were found:\n"; 

	foreach my $studyUID (keys(%hash)) {
	    print "'$studyUID'\n";
	}
	exit $NeuroDB::ExitCodes::NOT_A_SINGLE_STUDY;
    }
    else {
	my $studyid;
	while ( my ($key, $value) = each(%hash) ) {
	    $studyid = $key;
	}
	return $studyid;
    }
}


=pod

=head3 print_header()

Prints HEADER using the format defined in C<&format_head> function.

=cut

sub print_header {
    my $self = shift;
    $self->format_head($self);
}


=pod

=head3 format_head()

Format definition to print the head of the HEADER.

=cut

sub format_head {
    my $self = shift;
    $~ = 'FORMAT_HEADER';
    write();
    format FORMAT_HEADER =
<STUDY_INFO>
* Unique Study ID          :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{studyuid},                                
* Patient Name             :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{pname},
* Patient ID               :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{pid},                                
* Patient date of birth    :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{birthdate},
* Scan Date                :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{scandate},
* Patient Sex              :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{sex},
* Scanner Model Name       :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{scanner},
* Scanner Software Version :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{software},
* Institution Name         :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{institution},
* Modality                 :    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                $self->{header}->{modality}
</STUDY_INFO>
.
}


=pod 

=head3 print_content()

Prints the CONTENT using formats defined in C<&write_content_head>.

=cut

sub print_content {
    my $self = shift;
    my @files = @{$self->{'dcminfo'}};
    my ($d, $i) = 0;
    &write_content_head();
    foreach my $file (@files) {
	$file->[4]    = basename($file->[4]); # get rid of path to file
	if($file->[21]) { # file is dicom
	    &write_dcm(\$file);
	    $d++; # dicom count
	}
	else {
	    &write_other(\$file);
	}
	$i++; # count of all
    }
    print "</FILES>\n";
}


=pod

=head3 write_content_head()

Prints the Content head.

=cut

sub write_content_head {
    $~ = 'CONTENT_HEAD';
    write();
    format CONTENT_HEAD =
<FILES>
SN   | FN  | EN | Series                      | md5sum                           | File name
.
}


=pod

=head3 write_dcm($dcm)

Prints all DICOM files.

INPUT: array of DICOM information to print

=cut

sub write_dcm {
    my ($dcm) = @_;
    my $d = $$dcm;
    $~ = 'FORMAT_FILE';
    write();
# <FILES>
    format FORMAT_FILE =
@<<< | @<<<| @<<| @<<<<<<<<<<<<<<<<<<<<<<<<<< | @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<| @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  
$$d[1], $$d[3],$$d[2],$$d[12],                  $$d[20],                            $$d[4]
.
# </FILES>
}


=pod

=head3 write_other($dcm)

Prints all other files.

INPUT: array of other files information

=cut

sub write_other {
    my ($dcm) = @_;
    my $d = $$dcm;
    $~ = 'FORMAT_OTHER';
    write();
# <OTHER Files>
format FORMAT_OTHER =
----          Non DICOM File           ----   | @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<| @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  
                                                $$d[20],                           $$d[4]  
.
# </OTHER Files>
}


=pod

=head3 print_acquisitions()

Prints Acquisitions using formats from C<&write_acqu_head> and
C<&write_acqu_content>

=cut

sub print_acquisitions {
    my $self = shift;
    my @a = @{$self->{acqu_List}};
    &write_acqu_head();  # print the pseudo xml header
    my $i = 0;    
    foreach my $value (@a) { # loop through the acquisition summary hash
	&write_acqu_content($value);
	$i++;
    }
    print "</ACQUISITIONS>\n"; # print the pseudo xml footer
}


=pod

=head3 write_acqu_head()

Prints acquisition table header.

=cut

sub write_acqu_head {
    $~ = 'ACQU_HEADER';
    write();
    format ACQU_HEADER =
<ACQUISITIONS>
Series (SN) | Name of series                  | Seq Name        | echoT ms | repT ms  | invT ms  | sth mm | PhEnc | NoF            
.
}


=pod

=head3 write_acqu_content($acqu)

Prints acquisition's content.

INPUT: array of acquisition information to print

=cut

sub write_acqu_content {
    my $acqu = shift;
    my ($seriesNum, $sequName,  $echoT, $repT, $invT, $seriesName, $sl_thickness, $phaseEncode, $seriesUID, $num) = split(':::',$acqu);
    $~ = 'FORMAT_ACQU';
    write();
    format FORMAT_ACQU =
@<<<<<<<<<< | @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  | @<<<<<<<<<<<<<<<| @<<<<<<<<| @<<<<<<<<| @<<<<<<<<| @<<<<<<| @<<<< | @<<<<
$seriesNum,   $seriesName,                      $sequName,        $echoT,    $repT,     $invT,     $sl_thickness,   $phaseEncode, $num
.
}


=pod 

=head3 print_footer()

Prints footer using formats from C<&write_footer>.

=cut

sub print_footer {
    my $self = shift;
    $self->write_footer($self);
    my ($total, $acquNum, $acquName)  = @_;

    }


=pod

=head3 write_footer()

Prints footer summary information.

=cut

sub write_footer {
    my $self = shift;
    my $scanage = &date_format($self->{header}->{birthdate},$self->{header}->{scandate});
    $~ = 'FORMAT_FOOTER';
    write();
    format FORMAT_FOOTER =
<SUMMARY>
Total number of files   :   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                            $self->{totalcount},
Age at scan             :   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                            $scanage,
</SUMMARY>
.
}


=pod

=head3 dcmsummary()

Prints the whole thing using C<&print_header>, C<&print_content>,
C<&print_acquisitions> and C<&print_footer>. This is what you really want.

=cut

sub dcmsummary {
    my $self = shift;
    print "<STUDY>\n";
    $self->print_header();
    $self->print_content();
    $self->print_acquisitions();
    $self->print_footer();
    print "</STUDY>\n";
}


=pod

B<Unrelated but useful functions>

=head3 trimwhitespace($string)

Gets rid of nasty whitespace

INPUT: string to remove white space

RETURNS: string without white space

=cut

sub trimwhitespace {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}


=pod

=head3 date_format($first, $second)

If only one date argument is provided, then it will convert YYYYMMDD date
format into YYYY-MM-DD.
If two date arguments are provided, then it will compute the difference in
decimal and Y M +/- Days.

INPUTS: date to format, (optionally, a second date to get the difference
between two dates)

RETURNS: formatted date, or the different between two dates

=cut

sub date_format {
    my $first = $_[0];
    my $second = $_[1];
    return undef unless defined $first;
    if ($second) {
	my ($fY, $fM, $fD) = split("-", $first);
	my ($sY, $sM, $sD) = split("-", $second);
	my $Y = $sY - $fY;
	my $M = $sM - $fM;
	my $D = $sD - $fD;
	my $diff = &Math::Round::nearest(0.01, ($Y + $M/12.0 + $D/365.0)*1) . " or $Y years, $M months $D days";
	return $diff;
    }
    $first =~ s/(....)(..)(..)/$1-$2-$3/; 
    return $first; 
}


=pod

=head3 md5sum($filename)

Computes the MD5 sum of a file and outputs a format similar to C<md5sum> on
Linux.

INPUT: file name to use to compute MD5 sum

RETURNS: MD5 sum of the file

=cut

sub md5sum {
    my $filename = shift;
    open(FILE, $filename) or die "Can't open '$filename': $!";
    binmode(FILE);
    return Digest::MD5->new->addfile(*FILE)->hexdigest . "  $filename\n";
} 
1;


=pod

=head1 TO DO

Fix comments written as #fixme in the code.

=head1 LICENSING

Copyright (c) 2006 by J-Sebastian Muehlboeck, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

=head1 AUTHORS

J-Sebastian Muehlboeck,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
