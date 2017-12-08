# ------------------------------ MNI Header ----------------------------------
#@NAME       : DB::DBI
#@DESCRIPTION: Perform common tasks relating to database connectivity within the NeuroDB system
#@EXPORT     : look at the @EXPORT line below ;P
#@EXPORT_OK  : none
#@EXPORT_TAGS: none
#@USES       : Exporter, DBI (with DBD::mysql)
#@REQUIRES   : 
#@VERSION    : $Id: DBI.pm 3 2007-12-11 20:10:36Z jharlap $
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : sebas
#@COPYRIGHT  : Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#-----------------------------------------------------------------------------

package DB::DBI;

use Exporter ();
use DBI;

$VERSION = 0.1;
@ISA = qw(Exporter);

@EXPORT = qw(connect_to_db);
@EXPORT_OK = qw();

# ------------------------------ MNI Header ----------------------------------
#@NAME       : connect_to_db
#@INPUT      : optional: database, username, password, host
#@OUTPUT     : 
#@RETURNS    : DBI database handle
#@DESCRIPTION: connects to database 
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : sebas
#-----------------------------------------------------------------------------
sub connect_to_db
{
    my ($db_name, $db_user, $db_pass, $db_host) = @_;

    $db_name=""    unless $db_name;                    # database name
    $db_host=""    unless $db_host;                    # host name
    my $db_port="3306";

    my $db_dsn = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port;";

    $db_user = ""         unless $db_user;               # user name (fill in as appropriate)
    $db_pass = ""     unless $db_pass;               # password (ditto)

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass) or die "DB connection failed\nDBI Error: ".$DBI::errstr."\n";

    return $dbh;
}

sub getConfigSetting
{
    my ($dbh, $name) = @_;
    my ($message,$query,$where) = '';
    my $value = undef;

    $where = " WHERE c.ConfigID=(Select cs.ID from ConfigSettings cs where cs.Name=?)";
    $query = " SELECT c.Value FROM Config c";
    $query = $query . $where;
    my $sth = $$dbh->prepare($query);
    $sth->execute($name);
    if ( $sth->rows > 0 ) {
        $value = $sth->fetchrow_array();
    }
    return $value;
}

1;
