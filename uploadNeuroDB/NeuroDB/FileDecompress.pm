package NeuroDB::FileDecompress;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use Path::Class;
use Archive::Extract;
use Archive::Zip;


=pod
todo:
  - Set these global variables:
     + Archive::Extract::DEBUG  ----set this variable to true to have all calls to command line tools be printed out, including all their output
     + Archive::Extract::PREFER_BIN --- This variables controls whether Archive::Extract should prefer the use of perl modules, or commandline tools to extract archives.
     



=cut
################################################################
#####################Constructor ###############################
################################################################
sub new {
    my $params = shift;
    my ($file_path) = @_;
    my $self = {};
    my $extract_object = Archive::Extract->new( 
			archive => $file_path 
    );
    $self->{'extract_object'} = $extract_object;
    return bless $self, $params;
}


################################################################
#####################Extract()##################################
################################################################
################################################################
###This function will automatically detect the file-type########
####and will decompress the file by calling the appropriate##### 
######function under the hood and return boolean returns #######
######false if the decompressiong fails and true otherwise######
################################################################

sub Extract  {
    my $this = shift;
    my ($destination_folder) = @_;
    ###################################
    ##Check to see if the destination folder exists
   print "destination folder is " . $destination_folder;
    $this->{'extract_object'}->extract(to=>$destination_folder);
}
     

sub getArchivedFiles {
  my $this = shift;
  my $files = $this->{'extract_object'}->files;
  return $files;
}

sub getExtractedDirectory {
  my $this = shift;
  my $extracted_directory = $this->{'extract_object'}->extract_path()
  return $extracted_directory;


}

sub getType {
  my $this = shift;
  my $type = $this->{'extract_object'}->type;
  return $type;
}


##if there are issues:

  ### commandline tools, if found ###
  #$ae->bin_tar     # path to /bin/tar, if found
  #$ae->bin_gzip    # path to /bin/gzip, if found
  #$ae->bin_unzip   # path to /bin/unzip, if found
  #$ae->bin_bunzip2 # path to /bin/bunzip2 if found
  #$ae->bin_unlzma  # path to /bin/unlzma if found
  #$ae->bin_unxz    # path to /bin/unxz if found

1; 
