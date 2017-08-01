#! /usr/bin/perl

use strict;
use warnings;
use Getopt::Tabular;
use DB::DBI;

my $profile = undef;

my @opt_table = (
    [ "-profile", "string", 1, \$profile,
      "name of config file in ../dicom-archive/.loris_mri"
    ]
); 

my $Help = <<HELP;

This script will remove the root directory from the ArchiveLocation field
in the tarchive table to make path to the tarchive relative. This should 
be used once, when updating the LORIS-MRI code.

HELP

my $Usage = <<USAGE;

Usage: $0 -help to list options

USAGE

&Getopt::Tabular::SetHelp($Help, $Usage);
&Getopt::Tabular::GetOptions(\@opt_table, \@ARGV) || exit 1;

################################################################
################### input option error checking ################
################################################################
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named ".
          "'$profile' in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n";
    exit 2;
}

################################################################
######### Establish database connection ########################
################################################################
my $dbh = &DB::DBI::connect_to_db(@Settings::db);
print "\n==> Successfully connected to database \n";

################################################################
#### This setting is in the ConfigSettings table   #############
################################################################
my $tarchiveLibraryDir = &DB::DBI::getConfigSetting(
                            \$dbh,'tarchiveLibraryDir'
                            );
$tarchiveLibraryDir    =~ s/\/$//g;

################################################################
# Grep tarchive list in a hash                          ########
# %tarchive_list = {                                    ########
#      $TarchiveID => {                                 ########
#          'ArchiveLocation'    => $ArchiveLocation     ########
#          'NewArchiveLocation' => $newArchiveLocation  ########
#      }                                                ########
# };                                                    ########
################################################################
my %tarchive_list = &getTarchiveList( $dbh, $tarchiveLibraryDir );

################################################################
######### Update database with new ArchiveLocation #############
################################################################
&updateArchiveLocation( $dbh, %tarchive_list );


$dbh->disconnect();
print "Finished\n";
exit 0;


=pod
This function will grep all the TarchiveID and associated ArchiveLocation
present in the tarchive table and will create a hash of this information
including new ArchiveLocation to be inserted into the DB.
Input:  - $dbh = database handler
        - $tarchiveLibraryDir = where the tarchives are located
Output: - %tarchive_list = hash with tarchive info + newArchiveLocation
=cut
sub getTarchiveList {

    my ($dbh, $tarchiveLibraryDir) = @_;

    # Query to grep all tarchive entries
    ( my $query = <<QUERY ) =~ s/\n/ /g;
SELECT
  TarchiveID,
  ArchiveLocation
FROM
  tarchive
QUERY

    # Prepare and execute query
    my $sth = $dbh->prepare($query);
    $sth->execute();
    
    # Create tarchive list hash with old and new location
    my %tarchive_list;
    while ( my $rowhr = $sth->fetchrow_hashref()) {
    
        my $TarchiveID = $rowhr->{'TarchiveID'};
        my $ArchLoc    = $rowhr->{'ArchiveLocation'};
        my $newArchLoc = $ArchLoc;
        $newArchLoc    =~ s/$tarchiveLibraryDir\/?//g;
    
        $tarchive_list{$TarchiveID}{'ArchiveLocation'}    = $ArchLoc;
        $tarchive_list{$TarchiveID}{'NewArchiveLocation'} = $newArchLoc;
        
    }
    
    return %tarchive_list;

}

=pod
This function will update the tarchive table with the new ArchiveLocation.
Input:  - $dbh = database handler
        - $tarchive_list = hash with tarchive informations.
=cut
sub updateArchiveLocation {
    
    my ( $dbh, %tarchive_list ) = @_;

    # Update query
    (my $query = <<QUERY ) =~ s/\n/ /g; 
UPDATE
  tarchive
SET
  ArchiveLocation = ?
WHERE
  TarchiveID = ?
QUERY

    foreach my $TarID ( keys %tarchive_list ) {

        # values to use to execute the query
        my @query_values = ( 
                             $tarchive_list{$TarID}{'NewArchiveLocation'},
                             $TarID 
                           );

        # execute query
        my $sth = $dbh->prepare($query);
        $sth->execute(@query_values);

    }
}
