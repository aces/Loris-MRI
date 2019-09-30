#! /usr/bin/perl

=pod

=head1 NAME

gzip_nifti_files.pl -- Gzip all NIfTI files found in the LORIS database system

=head1 SYNOPSIS

perl gzip_nifti_files.pl C<[options]>

Available options are:

-profile: name of the config file in C<../dicom-archive/.loris_mri>


=head1 DESCRIPTION

The program gzip all NIfTI files found in the LORIS database system. It will first
grep the list of NIfTI files from the database (in the C<parameter_file> table).
Then, the program will loop through the found NIfTI files and:

- check that the file can be found on the filesystem (if not, it will issue a warning)

- check that the NIfTI file is not already gzipped

- create the gzipped NIfTI file

- replace the entry in the C<parameter_file> table with the new gzipped NIfTI file path

=head2 Methods

=cut

use strict;
use warnings;

use Getopt::Tabular;

use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;

use NeuroDB::Database;
use NeuroDB::DatabaseException;

use NeuroDB::objectBroker::ObjectBrokerException;
use NeuroDB::objectBroker::ConfigOB;

my $profile;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
        "name of config file in ../dicom-archive/.loris_mri"
    ]
);

my $Help = <<HELP;

The program gzip all NIfTI files found in the LORIS database system.

Documentation: perldoc gzip_nifti_files.pl

HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV)
    || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;



# ===========================================
## Input option error checking
# ===========================================

if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
        . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}




# ===========================================
## Establish database connection
# ===========================================

# old database connection
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);
print "\nSuccessfully connected to database \n";

# new Moose database connection
my $db  = NeuroDB::Database->new(
    databaseName => $Settings::db[0],
    userName     => $Settings::db[1],
    password     => $Settings::db[2],
    hostName     => $Settings::db[3]
);
$db->connect();




# ===========================================
## Get config setting using ConfigOB
# ===========================================

my $configOB = NeuroDB::objectBroker::ConfigOB->new(db => $db);

my $data_dir   = $configOB->getDataDirPath();
$data_dir      =~ s#/$##;




# ==================================================
## Grep the list of NIfTI files from the database
# ==================================================

(my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
      pf.Value
    FROM
      parameter_file pf JOIN parameter_type pt USING (ParameterTypeID)
    WHERE
      pt.Name = ?
QUERY
my $arr_ref = $dbh->selectall_arrayref($query, { Slice => {} }, "check_nii_filename");




# ==================================================
## Loop through each NIfTI file and gzip them
# ==================================================

foreach my $row (@$arr_ref) {
    my $nifti = $row->{Value};

    # go to the next row if NIfTI file already gzipped
    next if $nifti =~ m/.nii.gz$/;

    # check that the file is found on the filesystem
    my $nifti_full_path = "$data_dir/$nifti";
    unless (-e $nifti_full_path) {
        print "WARNING: could not find $nifti_full_path on the filesystem\n";
        next;
    }

    # create the gzipped NIfTI file
    my $gzip_nifti = &NeuroDB::MRI::gzip_file($nifti_full_path);
    unless ($gzip_nifti) {
        print "WARNING: Failure to create $gzip_nifti on the filesystem\n";
        next;
    }

    # update the database table with the gzip NIfTI path
    $gzip_nifti =~ s%$data_dir/%%g;
    update_parameter_file_nifti_value($nifti, $gzip_nifti, \$dbh);
}




$db->disconnect();
exit $NeuroDB::ExitCodes::SUCCESS;



=pod

=head3 update_parameter_file_nifti_value($nifti, $gzip_nifti, $dbh)

Update the C<parameter_file> to store the new gzipped NIfTI file location instead of
the uncompressed file path.

INPUT:
  - $nifti     : original path to the NIfTI file stored in the database
  - $gzip_nifti: path to the gzipped NIfTI file to update in the database
  - $dbh       : database handle

=cut

sub update_parameter_file_nifti_value {
    my ($nifti, $gzip_nifti, $dbh) = @_;

    my $update_query = "UPDATE parameter_file SET Value = ? WHERE Value = ?";

    my $sth = $$dbh->prepare($update_query);
    $sth->execute($gzip_nifti, $nifti);
}

__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
