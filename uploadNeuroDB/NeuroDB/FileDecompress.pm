package NeuroDB::FileDecompress;
use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use Path::Class;
use Archive::Extract;
use Archive::Zip;

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
=pod
Extract()
Description:
  - This function will automatically detect the file-type
    and will decompress the file by calling the appropriate
    function under the hood and return false if the decompression
    fails and true otherwise.
Arguments:
  $this              : reference to the class
  $destination_folder: Full path to the destination folder
  Returns            : True if success and false otherwise
=cut

sub Extract  {
    my $this = shift;
    my ($destination_folder) = @_;
    #####################################################
    ##Check to see if the destination folder exists######
    #####################################################
    return $this->{'extract_object'}->extract(to=>$destination_folder);
}


################################################################
#####################getArchivedFiles()#########################
################################################################
=pod
getArchivedFiles()
Description:
  - This function will return an array ref with the paths of 
    all the files in the archive.

Arguments:
  $this              : reference to the class
  Returns            : Array of a files
=cut

sub getArchivedFiles {
    my $this = shift;
    return  $this->{'extract_object'}->files;
}

################################################################
#####################getExtractedDirectory()####################
################################################################
=pod
getExtractedDirectory()
Description:
  - It will return the directory that the files will be extracted
    to. 

Arguments:
  $this              : Reference to the class
  Returns            : Path to the folder where file will be extracted
=cut

sub getExtractedDirectory {
    my $this = shift;
    return $this->{'extract_object'}->extract_path();
}

################################################################
#####################getType()##################################
################################################################
=pod
getType()
Description:
  - This function will return the type of the archive

Arguments:
  $this              : reference to the class
  Returns            : The type of the archive
=cut


sub getType {
    my $this = shift;
    return  $this->{'extract_object'}->type;
}
1; 
