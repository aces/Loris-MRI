# NAME

NeuroDB::Notify -- Provides an interface to the email notification subsystem
of LORIS

# SYNOPSIS

use NeuroDB::Notify;

my $notifier = NeuroDB::Notify->new(\\$dbh);

my $message           = "Some kind of message from tarchive validation";
my $upload\_id         = 123456;
my $notify\_notsummary = 'N';
$notifier->spool('tarchive validation', $message,   0,
		         'tarchiveLoader',      $upload\_id, 'Y',
		         $notify\_notsummary
		        );

# DESCRIPTION

This class defines an interface into the email notification subsystem of
LORIS - particularly with regards to spooling new messages.

## Methods

### new($dbh) (constructor)

Creates a new instance of this class. The parameter `\$dbh` is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

INPUT: DBI database handle

RETURNS: new instance of this class.

### spool($type, $message, $centerID, $origin, $processID, $isError, $isVerb)

Spools a new notification message, `$message`, into the spool for notification
type `$type`. If `$centerID` is specified, only recipients in that site will
receive the message.

INPUT:
  $type     : notification type
  $message  : notification message
  $centerID : center ID
  $origin   : notification origin
  $processID: process ID
  $isError  : if the notification is an error
  $isVerb   : if verbose is set

RETURNS: 1 on success, 0 on failure

### getTypeID($type)

Gets the notification typeID for the notification of type `$type`.

INPUT: notification type

RETURNS: the notification typeID, or undef is none exists

### getSpooledTypes()

Gets the notification types for which there are unsent messages spooled.

RETURNS: an array of hashrefs, each of which has keys NotificationTypeID and
SubjectLine and CenterID

### getSpooledMessagesByTypeID($typeID, $centerID)

Gets the spooled messages for a given NotificationTypeID specified by
`$typeID`, optionally directed to the center specified by `$centerID`.

INPUT: notification type ID, (optionally the center ID)

RETURNS: an array of hashrefs, each of which has keys TimeSpooled and Message

### getRecipientsByTypeID($typeID, $centerID)

Gets the recipient list for a given NotificationTypeID specified by
`$typeID`, optionally directed to the center specified by `$centerID`.

INPUT: notification type ID, (optionally the center ID)

RETURNS: an array of email addresses

### markMessagesAsSentByTypeID($typeID, $centerID)

Marks all messages as sent with a given NotificationTypeID specified by
`$typeID` and optionally `$centerID`.

INPUT: notification type ID, (optionally the center ID)

# TO DO

Nothing planned.

# BUGS

None reported.

# COPYRIGHT

Copyright (c) 2004 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
