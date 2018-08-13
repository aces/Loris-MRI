#! /usr/bin/perl

=pod

=head1 NAME

database_files_update.pl -- Updates path stored in C<files> and
C<parameter_file> tables so that they are relative to C<data_dir>

=head1 SYNOPSIS

perl database_files_update.pl C<[options]>

Available option is:

-profile: name of the config file in C<../dicom-archive/.loris_mri>

=head1 DESCRIPTION

This script updates the path stored in the C<files> and C<parameter_file>
tables to remove the C<data_dir> part of the path for security improvements.

=head2 Methods

=cut


use strict;
use warnings;
use Getopt::Tabular;
use NeuroDB::DBI;

my $profile =   undef;
my @args;

my $Usage   =   <<USAGE;

This script updates the path stored in the files and parameter_file tables to
remove the \$data_dir part of the path for security improvements.

Usage: perl database_files_update.pl [options]

Documentation: perldoc database_files_update.pl

-help for options

USAGE

my @args_table  =   (["-profile",   "string",   1,  \$profile,  "name of config file in ../dicom-archive/.loris_mri."]
                    );

Getopt::Tabular::SetHelp ($Usage, '');
GetOptions(\@args_table, \@ARGV, \@args)    ||  exit 1;

# Input option error checking
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if  ($profile && !@Settings::db)    { 
        print "\n\tERROR: You don't have a configuration file named '$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
            exit 33; 
}
if  (!$profile) { 
        print "$Usage\n\tERROR: You must specify a profile.\n\n";  
            exit 33;
}

# Establish database connection
my $dbh     =   &NeuroDB::DBI::connect_to_db(@Settings::db);

# these settings are in the database and can be set in the Configuration module of LORIS
my $data_dir = &NeuroDB::DBI::getConfigSetting(\$dbh,'dataDirBasepath');
$data_dir =~ s/\/$//;

# Needed for log file
my  $log_dir    =   "$data_dir/logs";
my  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)    =   localtime(time);
my  $date       =   sprintf("%4d-%02d-%02d_%02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my  $log        =   "$log_dir/replacePATH_$date.log";
open (LOG,">>$log");
print LOG "\n==> Successfully connected to database \n";
print LOG "Log file, $date\n\n";



#### Updating minc location in files table ####
my  ($minc_location_refs, $fileIDs_minc) =   get_minc_files($data_dir, $dbh);    # list all mincs with 'File'=~$data_dir in files table.
if  ($minc_location_refs) {
    foreach my $fileID (@$fileIDs_minc) {
        my  $new_minc_location  =   $minc_location_refs->{$fileID};
        $new_minc_location      =~  s/$data_dir\///i;
        my  ($rows_affected)    =   update_minc_location($fileID, $new_minc_location, $dbh); # update minc location in files table.
        if  ($rows_affected ==  1)  { 
            print LOG "Updated location of minc with $fileID FileID to $new_minc_location.\n";
        } else {
            print LOG "ERROR: $rows_affected while updating minc with $fileID FileID to $new_minc_location.\n";
        }
    }
} else {
    print LOG "No file was found with a path starting from the root directory (i.e. including $data_dir)\n";
}

#### Updating pic location in parameter_file table ####
my  ($pic_location_refs, $fileIDs_pic)  =   get_parameter_files($data_dir, 'check_pic_filename', $dbh);

if  ($pic_location_refs) {
    foreach my $fileID (@$fileIDs_pic) {
        my  $new_pic_location  =   $pic_location_refs->{$fileID};
        $new_pic_location      =~  s/$data_dir\///i;
        my  ($rows_affected)   =   update_parameter_file_location($fileID, $new_pic_location, 'check_pic_filename', $dbh); # update pic location in parameter_file table.
        if  ($rows_affected ==  1)  { 
            print LOG "Updated pic location with $fileID FileID to $new_pic_location.\n";
        } else {
            print LOG "ERROR: $rows_affected while updating pic location with $fileID FileID to $new_pic_location.\n";
        }
    }
} else {
    print LOG "No pic was found with a path starting from the root directory (i.e. including $data_dir)\n";
}


#### Updating tarchive location in parameter_file table ####
my  ($tarchive_location_refs, $fileIDs_tar)  =   get_parameter_files($data_dir, 'tarchiveLocation', $dbh);

if  ($tarchive_location_refs) {
    foreach my $fileID (@$fileIDs_tar) {
        my  $new_tarchive_location  =   $tarchive_location_refs->{$fileID};
        $new_tarchive_location      =~  s/$data_dir\///i;
        my  ($rows_affected)   =   update_parameter_file_location($fileID, $new_tarchive_location, 'tarchiveLocation', $dbh); # update tarchive location in parameter_file table.
        if  ($rows_affected ==  1)  { 
            print LOG "Updated tarchive location in parameter_file with $fileID FileID to $new_tarchive_location.\n";
        } else {
            print LOG "ERROR: $rows_affected while updating tarchive location in parameter_file with $fileID FileID to $new_tarchive_location.\n";
        }
    }
} else {
    print LOG "No tarchive was found in parameter_file with a path starting from the root directory (i.e. including $data_dir)\n";
}


###############
## Functions ##
###############

=pod

=head3 get_minc_files($data_dir, $dbh)

Gets the list of MINC files to update the location in the C<files> table.

INPUTS:
  - $data_dir: data directory (e.g. C</data/$PROJECT/data>)
  - $dbh     : database handle

RETURNS: hash of MINC locations, array of FileIDs

=cut

sub get_minc_files {
    my  ($data_dir, $dbh)   =   @_;

    my  (%minc_locations,@fileIDs);
    my  $query  =   "SELECT FileID, File "  .
                    "FROM files "           .
                    "WHERE File LIKE ?";
    my  $like   =   "%$data_dir%";
    my  $sth    =   $dbh->prepare($query);
    $sth->execute($like);

    if  ($sth->rows > 0) {
        while (my $row  = $sth->fetchrow_hashref()) { 
            my  $fileID =   $row->{'FileID'};
            push    (@fileIDs, $fileID); 
            $minc_locations{$fileID}    =   $row->{'File'};
        }
    } else {
        return  undef;
    }

    return  (\%minc_locations, \@fileIDs);
}


=pod

=head3 update_minc_location($fileID, $new_minc_location, $dbh)

Updates the location of MINC files in the C<files> table.

INPUTS:
  - $fileID           : file's ID
  - $new_minc_location: new MINC relative location
  - $dbh              : database handle

RETURNS: Number of rows affected by the update (should always be 1)

=cut

sub update_minc_location {
    my  ($fileID, $new_minc_location, $dbh) =   @_;  # update minc location in files table.

    my  $query          =   "UPDATE files " .
                            "SET File=? " .
                            "WHERE FileID=?";
    my  $sth            =   $dbh->prepare($query);
    my  $rows_affected  =   $sth->execute($new_minc_location,$fileID);

    return  ($rows_affected);
}


=pod

=head3 get_parameter_files($data_dir, $parameter_type, $dbh)

Gets list of PIC files to update location in the C<parameter_file> table by
removing the root directory from the path.

INPUTS:
  - $data_dir      : data directory (e.g. C</data$PROJECT/data>)
  - $parameter_type: name of the parameter type for the PIC
  - $dbh           : database handle

RETURNS: hash of PIC file locations, array of C<FileIDs>

=cut

sub get_parameter_files {
    my  ($data_dir, $parameter_type, $dbh)  =   @_;

    my (@fileIDs,%file_locations);

    my  $query  =   "SELECT pf.FileID, pf.Value " .
                    "FROM parameter_file AS pf "  .
                    "JOIN parameter_type AS pt "  .
                    "ON (pt.ParameterTypeID=pf.ParameterTypeID) " .
                    "WHERE pt.Name=? " .
                    "AND pf.Value LIKE ?";
    my  $like   =   "%$data_dir%";
    my  $sth    =   $dbh->prepare($query);
    $sth->execute($parameter_type,$like);

    if  ($sth->rows > 0) {
        while (my $row  = $sth->fetchrow_hashref()) {
            my  $fileID =   $row->{'FileID'};
            push    (@fileIDs, $fileID);
            $file_locations{$fileID}    =   $row->{'Value'};
        }
    } else {
        return  undef;
    }

    return  (\%file_locations, \@fileIDs);
}


=pod

=head3 update_parameter_file_location($fileID, $new_file_location, $parameter_type, $dbh)

Updates the location of PIC files in the C<parameter_file> table.

INPUTS:
  - $fileID           : file's ID
  - $new_file_location: new location of the PIC file
  - $parameter_type   : parameter type name for the PIC
  - $dbh              : database handle

RETURNS: number of rows affected by the update (should always be 1)

=cut

sub update_parameter_file_location {
    my  ($fileID, $new_file_location, $parameter_type, $dbh) =   @_; 

    my  $select         =   "SELECT ParameterTypeID " .
                            "FROM parameter_type "    .
                            "WHERE Name=?";
    my  $sth            =   $dbh->prepare($select);
    $sth->execute($parameter_type);    

    my  $ParameterTypeID;
    if  ($sth->rows > 0) {
        my  $rows       =   $sth->fetchrow_hashref();
        $ParameterTypeID=   $rows->{'ParameterTypeID'};
    }

    my  $query          =   "UPDATE parameter_file AS pf, parameter_type AS pt " .
                            "SET pf.Value=? " .
                            "WHERE pf.FileID=? " .
                            "AND pf.ParameterTypeID=?";
    my  $sth_update     =   $dbh->prepare($query);
    my  $rows_affected  =   $sth_update->execute($new_file_location,$fileID,$ParameterTypeID);

    return  ($rows_affected);   
}


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
