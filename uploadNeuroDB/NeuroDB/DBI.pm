package NeuroDB::DBI;

=pod

=head1 NAME

NeuroDB::DBI -- Allows LORIS database connectivity for LORIS-MRI code base


=head1 SYNOPSIS

  use NeuroDB::DBI;

  my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

  my $sth = $dbh->prepare($query);
  $sth->execute(@bind_value);

  my @row_array  = $sth->fetchrow_array;


=head1 DESCRIPTION

This package performs common tasks related to database connectivity between
the LORIS-MRI code base and the LORIS backend database.

=head2 Methods

=cut


use strict;
use warnings;
use DBI;


=pod

=head3 connect_to_db($db_name, $db_user, $db_pass, $db_host)

This method connects to the LORIS database (C<$db_database>) on host
(C<$db_host>) as username (C<$db_user>) & password (C<$db_pass>). The function
dies with a database connection error when the connection failed or returns a
DBI database handler.

INPUTS:
  - $db_name: database name (optional)
  - $db_user: database user (optional)
  - $db_pass: password for C<$db_user> (optional)
  - $db_host: database host (optional)

RETURNS: DBI database handler when connection is successful

=cut
sub connect_to_db
{
    my ($db_name, $db_user, $db_pass, $db_host) = @_;
    
    $db_name=""   unless $db_name;          # database name
    $db_host=""   unless $db_host;          # host name
    my $db_port="3306";

    my $db_dsn = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port;";
    $db_user = ""    unless $db_user;       # user name (fill in as appropriate)
    $db_pass = ""    unless $db_pass;       # password (ditto)

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass) or die
        "DB connection failed\nDBI Error: ". $DBI::errstr."\n";
      
    $dbh->{mysql_auto_reconnect} = 1;
    
    return $dbh;
}

1;

=pod

=head1 TO DO

Expand the package with more functions.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

=head1 AUTHORS

Jonathan Harlap,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
