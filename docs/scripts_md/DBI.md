# NAME

NeuroDB::DBI -- Allows LORIS database connectivity for LORIS-MRI code base

# SYNOPSIS

    use NeuroDB::DBI;

    my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

    my $sth = $dbh->prepare($query);
    $sth->execute(@bind_value);

    my @row_array  = $sth->fetchrow_array;

# DESCRIPTION

This package performs common tasks related to database connectivity between
the LORIS-MRI code base and the LORIS backend database.

## Methods

### connect\_to\_db($db\_name, $db\_user, $db\_pass, $db\_host)

This method connects to the LORIS database (`$db_database`) on host
(`$db_host`) as username (`$db_user`) & password (`$db_pass`). The function
dies with a database connection error when the connection failed or returns a
DBI database handler.

INPUTS:
  - $db\_name: database name (optional)
  - $db\_user: database user (optional)
  - $db\_pass: password for `$db_user` (optional)
  - $db\_host: database host (optional)

RETURNS: DBI database handler when connection is successful

### getConfigSetting($dbh, $name)

This method fetches the value (`$value`) stored in the `Config` table for a
specific config setting (`$name`) specified as an input.

INPUTS:
  - $dbh : database handler
  - $name: name of the config setting

RETURNS: value corresponding to the config setting in the `Config` table
         of LORIS

# TO DO

Expand the package with more functions.

# COPYRIGHT AND LICENSE

Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

Jonathan Harlap,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
