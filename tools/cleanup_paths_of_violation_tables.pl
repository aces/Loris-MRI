#! /usr/bin/perl

use strict;
use warnings;

use Getopt::Tabular;

use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;



my $profile;
my $profile_desc = "name of config file in ../dicom-archive/.loris_mri";

my @opt_table = (
    ["-profile", "string", 1, \$profile, $profile_desc]
);

my $Help = <<HELP;
*******************************************************************************
Clean up paths in the violation tables
*******************************************************************************

The program replaces the invalid MincFile path present in the three violation tables
(MRICandidateErrors, mri_violations_log and mri_protocol_violated_scans) by the
valid path of the image present in the trashbin subdirectory of the LORIS-MRI data
directory.

Documentation: perldoc cleanup_paths_of_violation_tables.pl

HELP
my $Usage = <<USAGE;
usage: $0 [options]
       $0 -help to list options

USAGE
&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit $NeuroDB::ExitCodes::GETOPT_FAILURE;



##############################
# input option error checking
##############################

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



#########################################################
# Establish database connection and grep config settings
#########################################################

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);



##################################################
# Update the MincFile field of MRICandidateErrors
##################################################

update_MincPath_field($dbh, 'MRICandidateErrors',          'ID',    'MincFile');
update_MincPath_field($dbh, 'mri_protocol_violated_scans', 'ID',    'minc_location');
update_MincPath_field($dbh, 'mri_violations_log',          'LogID', 'MincFile');



exit $NeuroDB::ExitCodes::SUCCESS;



=pod

=head3 update_MincPath_field($dbh, $table, $id_field, $file_field)

Greps all the files present in a given table and updates its location to the file
present in the trashbin subdirectory of the LORIS-MRI data directory.

INPUTS:
  - $dbh            : database handle reference
  - $table_name     : name of the table to update
  - $id_field_name  : name of the ID field of the table
  - $file_field_name: name of the field containing the file location in the table

=cut

sub update_MincPath_field {
    my ($dbh, $table_name, $id_field_name, $file_field_name) = @_;

    my $select_query = "SELECT * FROM $table_name";
    my $files_ref    = $dbh->selectall_arrayref($select_query, { Slice => {} } );

    my $update_query = "UPDATE $table_name SET $file_field_name = ? WHERE $id_field_name = ?";

    foreach my $file (@$files_ref) {
        my $new_path = determine_MincPath($dbh, $file, $table_name, $file_field_name);

        my $sth = $dbh->prepare($update_query);
        $sth->execute($new_path, $file->{$id_field_name}) if $new_path;
    }
}


=pod

=head3 determine_MincPath($dbh, $file_ref, $table_name, $file_field_name)

Determines the new file path of the file to use when updating the violation
tables.

INPUTS:
  - $dbh            : database handle reference
  - $file_ref       : hash with row information from the violation table
  - $table_name     : table name used to create the hash $file_ref
  - $file_field_name: file location field name in the violation table

RETURNS:
  - new file path to use to update the violation table
  - undef if the file is in C<mri_violations_log> with C<Severity>='warning' and
    no entry with the same C<SeriesUID> was found in the C<files> table

=cut

sub determine_MincPath {
    my ($dbh, $file_ref, $table_name, $file_field_name) = @_;

    my $seriesUID    = $file_ref->{SeriesUID};
    my $current_path = $file_ref->{$file_field_name};

    if ($table_name eq 'mri_violations_log') {

        # query the files table for a file with the same SeriesUID than the
        # file in the mri_violations_log table
        my $query = "SELECT File FROM files WHERE SeriesUID = ?";
        my @paths = @{ $dbh->selectall_arrayref($query, { Slice => {} }, $seriesUID ) };

        # If more than one file was found in the files table for that
        # SeriesUID print out a warning message and return undef
        if ($#paths > 1) {

            print "\nWARNING: more than one file was found in the files table "
                . "matching the SeriesUID $seriesUID from file $current_path "
                . "present in mri_violations_log.\n";

            return undef;

        }

        # return the file path from the files table if an entry was found in
        # the files table for the same SeriesUID
        return $paths[0]->{File} if (@paths);
    }

    # return the path in the trashbin directory for files not present in the
    # files table
    return NeuroDB::MRI::get_trashbin_file_rel_path($current_path);
}