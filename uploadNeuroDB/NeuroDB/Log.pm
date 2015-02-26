package NeuroDB::Log;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Path::Class;
use Archive::Extract;
use Archive::Zip;


################################################################
#####################Constructor ###############################
################################################################
sub new {
    my $params = shift;
    my ($dbhr,$logfile,$origin,$processid) = @_;
    unless(defined $dbhr) {
       croak(
           "Usage: ".$params."->new(\$databaseHandleReference)"
       );
    }
    my $self = {};
    ############################################################
    #### Create the log file ###################################
    ############################################################
    my $LogDir  = dirname($logfile);
    my $file_name = basename($logfile);
    my $dir = dir($LogDir);
    my $file = $dir->file($file_name);
    my $LOG = $file->openw();
    $LOG->autoflush(1);

    ############################################################
    ############### Create a settings package ##################
    ############################################################
    my $profile = "prod";
    {
     package Settings;
     do "$ENV{LORIS_CONFIG}/.loris_mri/$profile";
    }
   
    $self->{'LOG'} = $LOG;
    $self->{'verbose'} = $verbose;
    $self->{'LogDir'} = $LogDir;
    $self->{'dbhr'} = $dbhr;
    $self->{'debug'} = $debug;
    $self->{'logfile'} = $logfile;

    $self->{'origin'} = $origin;
    $self->{'ProcessID'} = $processid;
    return bless $self, $params;
}


################################################################
## writeLog ####################################################
## this is a useful function that will write Log messages ######
## if the useTable is

####Gets:
=pod

- Message, 
- the type of message (error or log)
- The origin of where the error is comging from
- The processID/UploadID if it's coming from Imaging-uploader 
--Todo: Name could be changed from processid to uploadid

----
 
if the write-to-log is enabled:
- 1) It will write into the log file
- 2) if the logtype is error then it will write into the error.log as well

if the write-to-table is enabled:

- 1) It will insert into the Log table:
----a) the LogTypeID which is extracted using the origin
----b) The processID/UploadID (which is the foreign key to 
-----The mri-upload table--if it doesn't come from the mri-upload
-----it will be empty..
----c) CreateTime----The time that it is created...
----d) The Log Message..
----e) It will be true if it's an error message
----f) And the CenterID


=cut

################################################################
sub writeLog
{

    my $this           = shift;
    my $use_log_table  = $Settings::use_log_table;
    my $use_log_file = $Settings::use_log_file;
    my ( $message,$failStatus) = @_;
 
    #############################################################
    #######print out the message#################################
    #############################################################
    if ( $this->{ debug } )
    {
        print $message;
    }

    #############################################################
    #######write the logs in the log file########################
    #############################################################
    if ( $use_log_file ) {

        $this->{LOG}->print($message);
        if ($failStatus) {
            $this->{LOG}->print(
                "program exit status: $failStatus"
            );
            `cat $this->{logfile}  >> $this->{LogDir}/error.log`;
            `rm -f $this->{logfile} `;
         }
        close $this->{LOG};
    }

    #############################################################
    #######write the logs in the log table#######################
    ############################################################# 
    print "use log table is " . $use_log_table . "\n";
    if ( $use_log_table ) {

        if ($failStatus) {
            my $is_error = 1;
        }
        my $log_type_id = $this->getLogTypeID();
        if ($log_type_id) {
            my $log_query = "INSERT INTO log (Message,CreatedTime) VALUES (?, now())";
            print "log query is " . $log_query  . "\n";
            print 'use_file_table' . $use_log_table;
            my $logsth    = ${$this->{'dbhr'}}->prepare($log_query);
            print "message is $message";
            my $result = $logsth->execute( $message );
            print "result is $result \n";
        }
        else { 
            print "log type id not found";
        }
    }

}

sub getLogTypes {}
sub getLogTypeID {
    my $this           = shift;
    my $log_type_id= ''; 
    my $query = "SELECT lt.LogTypeID FROM log l ".
             "JOIN log_types lt join (lt.LogTypeID = l.LogTypeID)".
             " WHERE lt.Origin =?";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute($this->{'origin'});
    if ($sth->rows> 0) {
        $log_type_id= $sth->fetchrow_array();
    }
   return $log_type_id; 
}
sub getLogs {}
sub getLogsByProcessID{}

0; 
