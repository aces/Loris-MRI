use strict;
use warnings;

package NeuroDB::HRRTSUM;

use File::Basename;
use File::Find;
use Digest::MD5;
use File::Type;
use Date::Parse;


=pod

=head3 new($params, $source_dir, $target_dir, $bic) >> (constructor)

Creates a new instance of this class.

INPUTS:
  - $source_dir : source directory of the HRRT study
  - $target_dir : target directory where to save the HRRT study
  - $bic        : boolean variable specifying if the dataset is a BIC dataset

RETURNS: new instance of this class.

=cut
sub new {
    my $params = shift;

    my ($source_dir, $target_dir, $bic) = @_;

    my $self = {};
    bless $self, $params;

    # set the source directory
    $self->{source_dir} = $source_dir;

    # get arrays of all files, ecat files only, and various file counts
    $self->{hrrt_files}    = [ $self->hrrt_content_list($self->{source_dir}) ];
    $self->{ecat_files}    = [ $self->grep_ecat_files_only($bic) ];
    $self->{ecat_count}    = scalar @{ $self->{ecat_files}  };
    $self->{total_count}   = scalar @{ $self->{hrrt_files} };
    $self->{nonecat_count} = $self->{total_count} - $self->{ecat_count};

    # get header information from the ecat file
    $self->{header} = {};
    $self->{header} = $self->read_all_ecat($bic);

    # get study information based on the first ecat file header information
    $self->{study_info} = {};
    $self->{study_info} = $self->determine_study_info();

    # set the source directory and the target directory of the HRRT study
    $self->{target_dir} = $target_dir . $self->{study_info}->{year_acquired};

    # get the user information
    $self->{user} = $ENV{'USER'};

    # if BIC dataset, grep info from the .m file
    if ($bic) {
        $self->{matlab_info} = {};
        $self->{matlab_info} = $self->read_matlab_file();
    }

    return $self;
}




=pod

=head3 hrrt_content_list($source_dir)

Grep the list of files in the source directory and return it.

INPUT: path to the source directory

RETURNS: array of sorted files found in the source directory

=cut
sub hrrt_content_list {
    my ($self, $source_dir) = @_;

    my @files;

    my $find_handler = sub {
        push @files, $File::Find::name if ( -f $File::Find::name );
    };
    find($find_handler, $source_dir);

    my @sorted_files = sort @files;

    return @sorted_files;
}




=pod

=head3 grep_ecat_files_only($bic)

Grep the ECAT files present in the HRRT folder.
Note, if the dataset is a BIC dataset, skip the test*.v file.

INPUT: the boolean variable specifying if the dataset is a BIC dataset

RETURNS: array of ECAT files

=cut
sub grep_ecat_files_only {

    my ( $self, $bic ) = @_;

    my @ecat_files;
    foreach my $file ( @{ $self->{hrrt_files} } ) {
        next if !( $file =~ /.v$/i ); # continue if not an ecat file (.v)
        # next if dataset from the BIC and its basename starts with "test"
        next if ( $bic && basename($file) =~ /^test/i );
        # if gone until here, then file is a valid ecat
        push ( @ecat_files, $file );
    }

    return @ecat_files;
}




=pod

=head3 read_ecat($ecat_file, $bic)

Read the header of the ECAT file given as an argument and store the header info
in the $self->{header}->{$ecat_file} hash.

INPUTS: the full path to the ECAT file and the boolean variable specifying if
the dataset is a BIC dataset

RETURNS: the header information of the ECAT file stored in the
$self->{header}->{filename} hash

=cut
sub read_ecat {
    my ( $self, $ecat_file, $bic ) = @_;

    my @info = `lmhdr $ecat_file`;
    chomp( @info ); # remove carriage return of each element

    my $scan_start_time;
    foreach my $line_nb ( @info ) {
        next unless ( $line_nb =~ / := / );
        my ($key, $val) = split( ' := ', $line_nb );
        # set header information
        $self->{header}->{$ecat_file}->{$key} = $val;
    }

    # overwrite the facility name to be BIC-MNI-MCGILL if it is a BIC dataset
    # otherwise, it will wrongly say the facility name is Johns Hopkins Univ...
    $self->{header}->{$ecat_file}->{facility_name} = "BIC-MNI_MCGILL" if ($bic);

    return $self->{header}->{$ecat_file};
}




=pod

=head3 read_all_ecat($bic)

Loop through all ECAT files to read their header info and store them in the
$self->{header} hash.

INPUT: the boolean variable specifying if the dataset is a BIC dataset

RETURNS: all ECAT files' header information stored in $self->{header} hash

=cut
sub read_all_ecat {
    my ( $self, $bic ) = @_;

    foreach my $ecat_file ( @{ $self->{ecat_files} } ) {
        $self->{header}->{$ecat_file} = {};
        $self->{header}->{$ecat_file} = $self->read_ecat( $ecat_file, $bic );
    }

    return $self->{header};
}




=pod

=head3 determine_study_info()

Determine the study information based on the first ECAT file header information.
Study information includes the acquisition date, the patient name, the
center name and the scanner information.

RETURNS: the study information hash appended to $self ($self->{study_info})

=cut
sub determine_study_info {
    my ($self) = shift;

    # grep the first ecat file to determine study information
    my $ecat_file = @{ $self->{ecat_files}  }[0];
    my $ecat_info = $self->{header}->{$ecat_file};

    # determine the acquisition date based on $self->{header}->{scan_start_time}
    my ($ss,$mm,$hh,$day,$month,$year,$zone) = strptime(
        $ecat_info->{scan_start_time}
    );
    $self->{study_info}->{date_acquired} = sprintf(
        "%4d-%02d-%02d", $year+1900, $month+1, $day
    );
    $self->{study_info}->{year_acquired} = sprintf("%4d", $year+1900);

    # set patient name, system type and center name
    $self->{study_info}->{system_type}  = $ecat_info->{system_type};
    $self->{study_info}->{patient_name} = $ecat_info->{patient_name};
    $self->{study_info}->{center_name}  = $ecat_info->{facility_name};

    # scanner info are hardcoded as it remains the same for all HRRT scanners
    $self->{study_info}->{manufacturer}  = "Siemens";
    $self->{study_info}->{scanner_model} = "HRRT";

    return $self->{study_info};
}



=pod

=head3 read_matlab_file()

=cut
sub read_matlab_file {
    my $self = shift;

    # grep the Matlab with study parameters file from the hrrt_files list
    my @matlab_files = grep ( /.m$/, @{ $self->{hrrt_files} } );
    my $matlab_file  = $matlab_files[0];

    open my $fh, '<', $matlab_file;
    chomp(my @info = <$fh>);
    close $fh;

    foreach my $line_nb ( @info ) {
        next unless ( $line_nb =~ / = / );
        my ($key, $val) = split( ' = ', $line_nb );
        $val =~ s/;\cM$//;
        # set header information
        $self->{matlab_info}->{$key} = $val;
    }

    return $self->{matlab_info};

}


=pod

=head3 md5sum($filename)

Computes MD5 sum of a file and outputs a format similar to md5sum on Linux.

=cut
sub md5sum {
    my ($filename) = @_;

    open(FILE, $filename) or die "Can't open '$filename': $!";
    binmode(FILE);

    return Digest::MD5->new->addfile(*FILE)->hexdigest . "  $filename\n";
}




=pod

=head3 database($dbh, $today, $md5sumArchive)

=cut
sub database {
    my ( $self, $dbh, $md5sumArchive, $upload_id ) = @_;

    ## check if hrrt archive already inserted based on md5sumArchive
    ( my $select_hrrtArchiveID = <<QUERY ) =~ s/\n/ /gm;
    SELECT HrrtArchiveID
    FROM   hrrt_archive
    WHERE  md5sumArchive = ?
QUERY
    my $sth = $dbh->prepare( $select_hrrtArchiveID );
    $sth->execute( $md5sumArchive) ;

    if ($sth->rows > 0) {
        my @row = $sth->fetchrow_array();
        print "\n\n PROBLEM: This study has already been archived. "
              . "HrrtArchiveID corresponding to this study is $row[0]\n\n";
        exit; #TODO 1: call ExitCode.pm to do proper exit code
    }


    ## INSERT INTO hrrt_archive
    ( my $hrrt_archive_insert_query = <<QUERY ) =~ s/\n/ /gm;
    INSERT INTO hrrt_archive SET
      PatientName   = ?,   CenterName        = ?,
      CreatingUser  = ?,   SourceLocation    = ?,
      EcatFileCount = ?,   NonEcatFileCount  = ?,
      DateAcquired  = ?,   DateFirstArchived = NOW(),
      md5sumArchive = ?,   DateLastArchived  = NOW()
QUERY

    my $study_info = $self->{study_info};
    my @values = (
        $study_info->{patient_name},    $study_info->{center_name},
        $self->{user},                  $self->{source_dir},
        $self->{ecat_count},            $self->{nonecat_count},
        $study_info->{date_acquired},   $md5sumArchive
    );

    $sth        = $dbh->prepare( $hrrt_archive_insert_query );
    my $success = $sth->execute( @values );
    unless ($success) {
        print "Failed running query:\n$hrrt_archive_insert_query\n\n\n";
    }

    ## SELECT the inserted HrrtArchiveID
    $sth = $dbh->prepare( $select_hrrtArchiveID );
    $sth->execute( $md5sumArchive );
    my $hrrtArchiveID = undef;
    if ($sth->rows > 0) {
        my @row        = $sth->fetchrow_array();
        $hrrtArchiveID = $row[0];
    }


    ## INSERT INTO hrrt_archive_files
    ( my $hrrt_archive_files_query = <<QUERY ) =~ s/\n/ /gm;
    INSERT INTO hrrt_archive_files SET
      HrrtArchiveID = ?,   Filename = ?,  Md5Sum = ?
QUERY
    $sth = $dbh->prepare($hrrt_archive_files_query);
    foreach my $ecat_file ( @{ $self->{ecat_files} } ) {
        my $md5sum = md5sum( $ecat_file );
        @values    = ( $hrrtArchiveID, basename($ecat_file), $md5sum );
        $sth->execute( @values );
    }


    ## UPDATE mri_upload_rel table with the HRRT archive ID
    (my $insert_mri_upload_rel = <<QUERY ) =~ s/\n//gm;
    INSERT INTO mri_upload_rel SET
      HrrtArchiveID = ?,   UploadID = ?
QUERY
    @values  = ( $hrrtArchiveID, $upload_id );
    $sth     = $dhb->prepare( $insert_mri_upload_rel );
    $success = $sth->execute( @values );

    return $success;
}

1;




# end of script

=pod

=head1 TO DO

- md5sum is an exact copy of the one in DCMSUM.pm. Now that the 2 repo are
merged, could move that function from those 2 libraries into a library that
can be accessed by dicomTar.pl and HRRT_PET_archive.pl

=head1 BUGS

None reported (or list of bugs)

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut