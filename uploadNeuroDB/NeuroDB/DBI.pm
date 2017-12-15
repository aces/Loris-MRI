package NeuroDB::DBI;

=pod

=head1 NAME

NeuroDB::DBI


=head1 SYNOPSIS

use NeuroDB::DBI;

my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

my $sth = $dbh->prepare($query);
$sth->execute(@bind_value);

my @row_array  = $sth->fetchrow_array;


=head1 DESCRIPTION

This package performs common tasks relating to database connectivity between
the LORIS-MRI code base and the LORIS backend database. The following methods
are available.

=cut


use strict;
use warnings;
use Exporter ();
use DBI;
use Pod::Usage;

=pod

=head2 connect_to_db

This methods connects to the LORIS database ($db_database) on host ($db_host)
as username ($db_user) & password ($db_pass).

C<connect_to_db($db_name, $db_user, $db_pass, $db_host);>

INPUT: optional: database, username, password, host

RETURNS: DBI database handler.

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

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass) or die "DB connection failed\nDBI Error: ". $DBI::errstr."\n";
    return $dbh;
}


1;

=pod

=head1 AUTHOR

Jonathan Harlap, McConnell Brain Imaging Centre, Montreal Neurological
Institute, McGill University.


=head1 COPYRIGHT AND LICENSE

=cut
