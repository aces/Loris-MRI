package NeuroDB::Notify;

=pod

=head1 NAME

NeuroDB::Notify -- Provides an interface to the email notification subsystem of NeuroDB

=head1 SYNOPSIS

TBD

=head1 DESCRIPTION

This class defines an interface into the email notification subsystem
of NeuroDB - particularly with regards to spooling new messages.

=head1 METHODS

=cut

use strict;
use Carp;
use Data::Dumper;
my $VERSION = sprintf "%d.%03d", q$Revision: 1.1.1.1 $ =~ /: (\d+)\.(\d+)/;

=pod

B<new( \$dbh )> (constructor)

Create a new instance of this class.  The parameter C<\$dbh> is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

Returns: new instance of this class.

=cut

sub new {
    my $params = shift;
    my ($dbhr) = @_;
    unless(defined $dbhr) {
	croak("Usage: ".$params."->new(\$databaseHandleReference)");
    }

    my $self = {};
    $self->{'dbhr'} = $dbhr;
    return bless $self, $params;
}

=pod

B<spool( C<$type>, C<$message>, C<$centerID>, C<$origin>, C<$processID>, C<$isError> )>

Spools a new notification message, C<$message>, into the spool for
notification type C<$type>, unless the exact same message (including
type) is already in the spool.  If C<$centerID> is specified, only
recipients in that site will receive the message.

Returns: 1 on success, 0 on failure

=cut

sub spool {
    my $this = shift;
    my ($type, $message, $centerID, $origin, $processID, $isError) = @_;
    my $dbh = ${$this->{'dbhr'}};
    my @params = ();
    
    my $typeID = $this->getTypeID($type);
    return 0 unless defined $typeID;

    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT 
        COUNT(*) AS counter 
    FROM
        notification_spool
    WHERE 
        NotificationTypeID=?
        AND Message=?
        AND Sent='N'
QUERY

    push @params, $typeID;
    push @params, $message;

    if ($centerID) {
    	$query .= " AND CenterID= ? ";
        push @params, $centerID;	
    }
    if ($origin) {
    	$query .= " AND Origin= ? ";
        push @params, $origin;
    }
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);    
    my $row = $sth->fetchrow_hashref();
    
    if ($row->{'counter'} == 0) {

	    my @insert_params = ();
        ($query = <<QUERY) =~ s/\n/ /gm;
    INSERT INTO 
        notification_spool 
    SET 
        NotificationTypeID=?,
        TimeSpooled=NOW(), 
        Message=?
QUERY

        push @insert_params, $typeID;
        push @insert_params, $message;

        if ($centerID) {
            $query .= " , CenterID=? ";
            push @insert_params, $centerID;
        }
        if ($origin) {
            $query .= " , Origin=? ";
            push @insert_params, $origin;
        }

        if ($processID) {
            $query .= " , ProcessID=? ";
            push @insert_params, $processID;
        }

        if ($isError) {
            $query .= " , Error=? ";
            push @insert_params, $isError;
        }
        my $insert = $dbh->prepare($query);
        $insert->execute(@insert_params);
    }
    
    return 1;
}

=pod

B<getTypeID( C<$type> )>

Gets the notification typeID for the notification of type C<$type>.

Returns: the notification typeID, or undef is none exists

=cut

sub getTypeID {
    my $this = shift;
    my ($type) = @_;

    my $dbh = ${$this->{'dbhr'}};

    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT 
        NotificationTypeID 
    FROM
        notification_types 
    WHERE 
        Type=?
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute($type);

    if($sth->rows > 0) {
	my $row = $sth->fetchrow_hashref();
	return $row->{'NotificationTypeID'};
    } else {
	return undef;
    }
}

=pod

B<getSpooledTypes()>

Gets the notification types for which there are unsent messages spooled.

Returns: an array of hashrefs, each of which has keys NotificationTypeID and SubjectLine and CenterID

=cut

sub getSpooledTypes {
    my $this = shift;
    my $dbh = ${$this->{'dbhr'}};

    (my $query = <<QUERY) =~ s/\n/ /gm; 
    SELECT 
        DISTINCT t.NotificationTypeID, 
        t.SubjectLine, 
        s.CenterID 
    FROM 
        notification_types AS t, 
        notification_spool AS s 
    WHERE 
        t.NotificationTypeID = s.NotificationTypeID 
        AND s.Sent='N'
QUERY
    my $sth = $dbh->prepare($query);
    $sth->execute();

    my @types = ();
    if($sth->rows > 0) {
	while(my $row = $sth->fetchrow_hashref()) {
            push @types, $row;
        }
    }

    return @types;
}

=pod

B<getSpooledMessagesByTypeID( C<$typeID> )>

Gets the spooled messages for a given NotificationTypeID specified by
C<$typeID>, optionally directed to the center specified by
C<$centerID>.

Returns: an array of hashrefs, each of which has keys TimeSpooled and Message

=cut

sub getSpooledMessagesByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my @param;
    push(@param, $typeID);
    (my $query = <<QUERY) =~ s/\n/ /gm; 
    SELECT 
        TimeSpooled, 
        Message 
    FROM 
        notification_spool 
    WHERE 
        NotificationTypeID = ? 
        AND Sent='N'
QUERY
    if ($centerID) {
        $query .= " AND CenterID=? ";
        push(@param, $centerID);
    }
    $query .= " ORDER BY TimeSpooled";
    my $sth = $dbh->prepare($query);
    $sth->execute(@param);

    my @messages = ();
    if($sth->rows > 0) {
	while(my $row = $sth->fetchrow_hashref()) {
            push @messages, $row;
        }
    }

    return @messages;
}

=pod

B<getRecipientsByTypeID( C<$typeID>, C<$centerID> )>

Gets the recipient list for a given NotificationTypeID specified by
C<$typeID>, optionally directed to the center specified by C<$centerID>.
 
Returns: an array of email addresses

=cut

sub getRecipientsByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my @param;
    push(@param, $typeID);
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT
        users.email 
    FROM
        users, 
        notification_users 
    WHERE 
        users.UserID=notification_users.UserID 
        AND NotificationTypeID = ?
QUERY
    if ($centerID) {
        $query .= " AND CenterID=?";
        push(@param, $centerID);
    }
    my $sth = $dbh->prepare($query);
    $sth->execute(@param);

    my @recipients = ();
    if($sth->rows > 0) {
	while(my $row = $sth->fetchrow_hashref()) {
            push @recipients, $row->{'email'};
        }
    }

    return @recipients;
}

=pod

B<markMessagesAsSentByTypeID( C<$typeID>, C<$centerID> )>

Marks all messages as sent with a given NotificationTypeID specified by C<$typeID> and optionally C<$centerID>.

=cut

sub markMessagesAsSentByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my @param;
    push(@param, $typeID);
    (my $query = <<QUERY) =~ s/\n/ /gm;
    UPDATE 
        notification_spool 
    SET 
        Sent='Y' 
    WHERE 
        NotificationTypeID = ?
        AND Sent='N'
QUERY
    if ($centerID) {
        $query .= " AND CenterID=? ";
        push(@param, $centerID);
    }
    $query .= " AND CenterID='$centerID'";
    my $sth = $dbh->prepare($query);
    $sth->execute(@param);
}

1;

__END__

=pod

=head1 TO DO

Nothing planned.

=head1 BUGS

None reported.

=head1 COPYRIGHT

Copyright (c) 2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

=head1 AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>

=cut    
