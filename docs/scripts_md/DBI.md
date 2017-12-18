# NAME

NeuroDB::DBI

# SYNOPSIS

use NeuroDB::DBI;

my $dbh = &NeuroDB::DBI::connect\_to\_db(@Settings::db);

my $sth = $dbh->prepare($query);
$sth->execute(@bind\_value);

my @row\_array  = $sth->fetchrow\_array;

# DESCRIPTION

This package performs common tasks relating to database connectivity between
the LORIS-MRI code base and the LORIS backend database. The following methods
are available.

## connect\_to\_db

`$dbh = connect_to_db($db_name, $db_user, $db_pass, $db_host);`

This method connects to the LORIS database ($db\_database) on host ($db\_host)
as username ($db\_user) & password ($db\_pass). The function dies with a
database connection error when the connection failed or returns a DBI database
handler.

INPUT: optional: database, username, password, host

RETURNS: DBI database handler when connection is successful

## getConfigSetting

`$config_value = getConfigSetting($dbh, $name)`

This method fetches the value ($value) stored in the Config table for a
specific config setting ($name) specified as an input.

INPUT: database handler, name of the config setting

RETURNS: value corresponding to the config setting in the Config table of LORIS

# AUTHOR

Jonathan Harlap, McConnell Brain Imaging Centre, Montreal Neurological
Institute, McGill University.
