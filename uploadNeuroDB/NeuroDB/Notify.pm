package NeuroDB::Notify;


=pod

=head1 NAME

NeuroDB::Notify -- Provides an interface to the email notification subsystem
of LORIS

=head1 SYNOPSIS

  use NeuroDB::Notify;

  my $notifier = NeuroDB::Notify->new(\$dbh);

  my $message           = "Some kind of message from tarchive validation";
  my $upload_id         = 123456;
  my $notify_notsummary = 'N';
  $notifier->spool('tarchive validation', $message,   0,
  		   'tarchiveLoader',      $upload_id, 'Y',
  		   $notify_notsummary
  	          );


=head1 DESCRIPTION

This class defines an interface into the email notification subsystem of
LORIS - particularly with regards to spooling new messages.

=head2 Methods

=cut

use strict;
use Carp;
use Data::Dumper;
my $VERSION = sprintf "%d.%03d", q$Revision: 1.1.1.1 $ =~ /: (\d+)\.(\d+)/;


=pod

=head3 new($dbh) >> (constructor)

Creates a new instance of this class. The parameter C<$dbh> is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

INPUT: DBI database handle

RETURNS: new instance of this class.

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

=head3 spool($type, $message, $centerID, $origin, $processID, $isError, $isVerb)

Spools a new notification message, C<$message>, into the C<notification_spool>
table for notification type C<$type>. If C<$centerID> is specified, only
recipients in that site will receive the message.

INPUTS:
  - $type     : notification type
  - $message  : notification message
  - $centerID : center ID
  - $origin   : notification origin
  - $processID: process ID
  - $isError  : if the notification is an error
  - $isVerb   : if verbose is set

RETURNS: 1 on success, 0 on failure

=cut

sub spool {
    my $this = shift;
    my ($type, $message, $centerID, $origin, $processID, $isError, $isVerb) = @_;
    my $dbh = ${$this->{'dbhr'}};
    my @params = ();
    
    my $typeID = $this->getTypeID($type);
    return 0 unless defined $typeID;

    my @insert_params = ();
    my $query = "INSERT INTO notification_spool SET NotificationTypeID=?,
                TimeSpooled=NOW(), 
                Message=? ";

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

    if ($isVerb) {
        $query .= " , Verbose=? ";
        push @insert_params, $isVerb;
    }
    my $insert = $dbh->prepare($query);
    $insert->execute(@insert_params);
    
    return 1;
}


=pod

=head3 getTypeID($type)

Gets the notification type ID for the notification of type C<$type>.

INPUT: notification type

RETURNS: the notification typeID, or undef if none exists

=cut

sub getTypeID {
    my $this = shift;
    my ($type) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my $query = "SELECT NotificationTypeID FROM notification_types WHERE Type=".$dbh->quote($type);
    my $sth = $dbh->prepare($query);
    $sth->execute();

    if($sth->rows > 0) {
	my $row = $sth->fetchrow_hashref();
	return $row->{'NotificationTypeID'};
    } else {
	return undef;
    }
}


=pod

=head3 getSpooledTypes()

Gets the notification types for which there are unsent messages spooled.

RETURNS: an array of hash ref, each of which has keys C<NotificationTypeID> and
C<SubjectLine> and C<CenterID>

=cut

sub getSpooledTypes {
    my $this = shift;
    my $dbh = ${$this->{'dbhr'}};

    my $query = "SELECT DISTINCT t.NotificationTypeID, t.SubjectLine, s.CenterID FROM notification_types AS t, notification_spool AS s WHERE t.NotificationTypeID = s.NotificationTypeID AND s.Sent='N'";
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

=head3 getSpooledMessagesByTypeID($typeID, $centerID)

Gets the spooled messages for a given C<NotificationTypeID> specified by
C<$typeID>, optionally directed to the center specified by C<$centerID>.

INPUTS:
  - $typeID  : notification type ID
  - $centerID: the center ID (optional)

RETURNS: an array of hash refs, each of which has keys C<TimeSpooled> and
C<Message>

=cut

sub getSpooledMessagesByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my $query = "SELECT TimeSpooled, Message FROM notification_spool WHERE NotificationTypeID = $typeID AND Sent='N'";
    $query .= " AND CenterID='$centerID'" if $centerID;
    $query .= " ORDER BY TimeSpooled";
    my $sth = $dbh->prepare($query);
    $sth->execute();

    my @messages = ();
    if($sth->rows > 0) {
	while(my $row = $sth->fetchrow_hashref()) {
            push @messages, $row;
        }
    }

    return @messages;
}


=pod

=head3 getRecipientsByTypeID($typeID, $centerID)

Gets the recipient list for a given C<NotificationTypeID> specified by
C<$typeID>, optionally directed to the center specified by C<$centerID>.

INPUTS:
  - $typeID  : notification type ID
  - $centerID: the center ID (optional)

RETURNS: an array of email addresses

=cut

sub getRecipientsByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my $query = "SELECT users.email FROM users, notification_users WHERE users.UserID=notification_users.UserID AND NotificationTypeID = $typeID";
    $query .= " AND CenterID='$centerID'" if $centerID;
    my $sth = $dbh->prepare($query);
    $sth->execute();

    my @recipients = ();
    if($sth->rows > 0) {
	while(my $row = $sth->fetchrow_hashref()) {
            push @recipients, $row->{'email'};
        }
    }

    return @recipients;
}


=pod

=head3 markMessagesAsSentByTypeID($typeID, $centerID)

Marks all messages as sent with a given C<NotificationTypeID> specified by
C<$typeID> and optionally C<$centerID>.

INPUTS:
  - $typeID  : notification type ID
  - $centerID: the center ID (optional)

=cut

sub markMessagesAsSentByTypeID {
    my $this = shift;
    my ($typeID, $centerID) = @_;

    my $dbh = ${$this->{'dbhr'}};

    my $query = "UPDATE notification_spool SET Sent='Y' WHERE NotificationTypeID = $typeID AND Sent='N'";
    $query .= " AND CenterID='$centerID'" if $centerID;
    $dbh->do($query);
}

1;

__END__

=pod

=head1 COPYRIGHT

Copyright (c) 2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

=head1 AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut    
