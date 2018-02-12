# Generic TODOs:

##TODO 1: once ExitCodes.pm class merged, replace exit codes by the variables
# from that class


use strict;
use warnings;
use Getopt::Tabular;
use File::Temp qw/ tempdir /;
use Date::Parse;


###### Import NeuroDB libraries to be used
use NeuroDB::DBI;
##TODO 1: add line use NeuroDB::ExitCodes;


##TODO 1: move those exit codes to ExitCodes.pm


###### Table-driven argument parsing

# Initialize variables for Getopt::Tabular
my $profile       = undef;


