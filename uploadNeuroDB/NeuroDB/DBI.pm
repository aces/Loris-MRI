# ------------------------------ MNI Header ----------------------------------
#@NAME       : NeuroDB::DBI
#@DESCRIPTION: Perform common tasks relating to database connectivity within the NeuroDB system
#@EXPORT     : look at the @EXPORT line below ;P
#@EXPORT_OK  : none
#@EXPORT_TAGS: none
#@USES       : Exporter, DBI (with DBD::mysql)
#@REQUIRES   : 
#@VERSION    : $Id: DBI.pm,v 1.3 2006/09/21 18:45:25 moi Exp $
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : sebas
#@COPYRIGHT  : Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#-----------------------------------------------------------------------------

package NeuroDB::DBI;

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
#@DESCRIPTION: connects to database (default: qnts_dev) on host (default montague) 
#              as username & password (default: mriscript)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : sebas
#-----------------------------------------------------------------------------
sub connect_to_db
{
    my ($db_name, $db_user, $db_pass, $db_host) = @_;
    
    $db_name=""   unless $db_name;           # database name
    $db_host=""   unless $db_host;           # host name
    my $db_port="3306";

    my $db_dsn = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port;";
    $db_user = ""    unless $db_user;               # user name (fill in as appropriate)
    $db_pass = ""    unless $db_pass;               # password (ditto)

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass) or die "DB connection failed\nDBI Error: ". $DBI::errstr."\n";
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




=pod

=head3 getHrrtUploadInfo($dbh, $upload_id)

Fetches C<UploadLocation>, C<DecompressedLocation> and C<HrrtArchiveID> from
the database based on the provided C<UploadID>.

INPUTS: database handler and c<UploadID>

RETURNS: undef if no entry was found for the given C<UploadID> or a hash
containing C<UploadLocation>, C<DecompressedLocation> and C<HrrtArchiveID>
information for the C<UploadID>

=cut

sub getHrrtUploadInfo {
    my ($dbh, $upload_id) = @_;

    # grep the UploadedLocation for the UploadID
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT UploadLocation, DecompressedLocation, HrrtArchiveID
    FROM mri_upload
    LEFT JOIN mri_upload_rel ON ( mri_upload.UploadID = mri_upload_rel.UploadID )
    WHERE mri_upload.UploadID=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($upload_id);

    # returns undef if no mri_upload entry found
    return undef unless ($sth->rows > 0);

    # grep the result of the query into $self->{upload_info} hash
    my @result = $sth->fetchrow_array();
    my $upload_info = {};
    $upload_info->{upload_location}       = $result[0];
    $upload_info->{decompressed_location} = $result[1];
    $upload_info->{hrrt_archive_ID}       = $result[2];

    return $upload_info;
}




sub getRegisteredFileIdUsingMd5hash {
    my ( $fileref, $dbh ) = @_;

    my $md5hash = &NeuroDB::MRI::compute_hash($fileref);

    (my $query = <<QUERY) =~ s/\n/ /g;
    SELECT FileID
    FROM   files
      JOIN parameter_file USING (FileID)
      JOIN parameter_type USING (ParameterTypeID)
    WHERE  Name = 'md5hash' AND Value=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($md5hash);

    # returns undef if no mri_upload entry found
    return undef unless ($sth->rows > 0);

    # grep the result of the query
    my @result    = $sth->fetchrow_array();
    my $fileID    = $result[0];

    return $fileID;
}



sub getSessionIdFromFileId {
    my ( $fileID, $dbh ) = @_;

    my $query = "SELECT SessionID FROM files WHERE FileID=?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($fileID);

    # returns undef if no rows returned
    return undef unless ($sth->rows > 0);

    # grep the result of the query
    my @result     = $sth->fetchrow_array();
    my $sessionID = $result[0];

    return $sessionID;

}



sub updateHrrtArchiveSessionID {
    my ($hrrtArchiveID, $sessionID, $dbh) = @_;

    my $query = "UPDATE hrrt_archive SET SessionID=? WHERE HrrtArchiveID=?";
    my $sth   = $dbh->prepare($query);
    $sth->execute($sessionID, $hrrtArchiveID);

}


sub updateHrrtUploadInfo {
    my ($valuesRef, $upload_id, $dbh) = @_;

    my @fields = ();
    my @values = ();
    foreach my $field (keys %$valuesRef) {
        push(@fields, "$field=?");
        push(@values, $$valuesRef{$field});
    }

    my $query  = sprintf(
        "UPDATE mri_upload SET %s WHERE %s",
        join(',', @fields),
        $upload_id
    );

    my $sth = $dbh->prepare($query);
    $sth->execute(@values);

}


1;
