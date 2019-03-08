package NeuroDB::File;

use English;
use Carp;

=pod

=head1 NAME

NeuroDB::File -- Provides an interface to the MRI file management subsystem of
LORIS

=head1 SYNOPSIS

 use NeuroDB::File;
 use NeuroDB::DBI;

 my $dbh = NeuroDB::DBI::connect_to_db();

 my $file = NeuroDB::File->new(\$dbh);

 my $fileID = $file->findFile('/path/to/some/file');
 $file->loadFile($fileID);

 my $acquisition_date = $file->getParameter('acquisition_date');
 my $parameters_hashref = $file->getParameters();

 my $coordinate_space = $file->getFileDatum('CoordinateSpace');
 my $filedata_hashref = $file->getFileData();


 # less common to use methods, available mainly for register_db...
 my $dbh_copy = $file->getDatabaseHandleRef();

 $file->loadFileFromDisk('/path/to/some/file');
 $file->setFileData('CoordinateSpace', 'nonlinear');
 $file->setParameter('patient_name', 'Larry Wall');

 my $parameterTypeID = $file->getParameterTypeID('patient_name');

=head1 DESCRIPTION

This class defines a MRI (or related) file (minc, bicobj, xfm,
etc) as represented within the LORIS database system.

B<Note:> if a developer does something naughty (such as leaving out
the database handle ref when instantiating a new object or so on) the
class will croak.

=head2 Methods

=cut


use strict;

use constant MAX_DICOM_PARAMETER_LENGTH => 1000;

my $VERSION = sprintf "%d.%03d", q$Revision: 1.6 $ =~ /: (\d+)\.(\d+)/;

=pod

=head3 new(\$dbh) >> (constructor)

Create a new instance of this class. The parameter C<\$dbh> is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

INPUT: DBI database handle.

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

=head3 loadFile($fileID)

Load the object with all the data pertaining to a file as defined by
parameter C<$fileID>.

INPUT: ID of the file to load.

RETURNS: 0 if no file was found, 1 otherwise.

=cut

sub loadFile {
    my $this = shift;
    my ($fileID) = @_;

    my $query = "SELECT * FROM files WHERE FileID=$fileID";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return 0;
    }
    $this->{'fileData'} = $sth->fetchrow_hashref();

    $query = "SELECT Name, Value FROM parameter_file left join parameter_type USING (ParameterTypeID) WHERE FileID=$fileID";
    $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return 0;
    }

    $this->{'parameters'} = {};
    while(my $paramref = $sth->fetchrow_hashref()) {
	$this->{'parameters'}->{$paramref->{'Name'}} = $paramref->{'Value'};
    }

    return 1;
}

=pod

=head3 findFile($filename)

Finds the C<FileID> pertaining to a file as defined by parameter C<$filename>,
which is a full C</path/to/file>.

INPUT: full path to the file to look for an ID in the database.

RETURNS: (int) FileID or undef if no file was found.

=cut

sub findFile {
    my $this = shift;
    my ($file) = @_;

    my $query = "SELECT FileID FROM files WHERE File='$file'";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return undef;
    } else {
	my $row = $sth->fetchrow_hashref();
	return $row->{'FileID'};
    }
}
    

=pod

=head3 getFileData()

Gets the set of file data (data from the C<files> table in the database).

RETURNS: hashref of the contents of the record in the C<files> table for the
loaded file.

=cut

sub getFileData {
    my $this = shift;
    return $this->{'fileData'};
}

=pod

=head3 getFileDatum($datumName)

Gets one element from the file data (data from the C<files> table in the
database).

INPUT: name of the element to get.

RETURNS: scalar of the particular datum requested pertaining to the loaded file.

=cut

sub getFileDatum {
    my $this = shift;
    my ($propertyName) = @_;

    return $this->{'fileData'}->{$propertyName};
}

=pod

=head3 getParameter($parameterName)

Gets one element from the file's parameters (data from the C<parameter_file>
table in the database).

INPUT: name of the element from the file's parameter

RETURNS: scalar of the particular parameter requested pertaining to the loaded
file.

=cut

sub getParameter {
    my $this = shift;
    my ($paramName) = @_;

    return $this->{'parameters'}->{$paramName};
}

=pod

=head3 getParameters()

Gets the set of parameters for the loaded file (data from the C<parameter_file>
table in the database).

RETURNS: hashref of the records in the C<parameter_file> table for the loaded
file.

=cut

sub getParameters {
    my $this = shift;
    return $this->{'parameters'};
}

=pod

=head3 getDatabaseHandleRef()

Gets the database handle reference which the object is using internally.

RETURNS: DBI database handle reference.

=cut

sub getDatabaseHandleRef {
    my $this = shift;
    return $this->{'dbhr'};
}


=pod

=head3 getFileType($file)

Determines the imaging file type based on the extension of the file to insert
and the list of available types in the C<ImagingFileTypes> table of the
database.

INPUT: the path to the imaging file to determine the file type

RETURNS: the type of the imaging file given as an argument

=cut

sub getFileType {
    my ($this, $file) = @_;

    my $fileType;

    # grep possible file types from the database
    (my $query = <<QUERY) =~ s/\n/ /gm;
    SELECT type
    FROM   ImagingFileTypes
QUERY
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    # else, loop through the different values from ImagingFileTypes table
    # and see if $file matches one of the file types.
    while (my $fileTypeRow = $sth->fetchrow_hashref()) {
        if ($file =~ /\.$fileTypeRow->{'type'}(\.gz)?$/) {
            $fileType = $fileTypeRow->{'type'};
        }
    }

    return $fileType;
}


=pod

=head3 loadFileFromDisk($filename)

Reads the headers from the file specified by C<$filename> and loads the current
object with the resultant parameters.

INPUT: file to read the headers from.

RETURNS: 0 if any failure occurred or 1 otherwise.

=cut

sub loadFileFromDisk {
    my $this = shift;
    my ($file) = @_;

    # try to untaint the filename
    if($file =~ /[\`;]/ || $file =~ /\.\./) {
	croak("loadFileFromDisk: $file is not a valid filename");
    }
    unless($file =~ /^\//) {
        croak("loadFileFromDisk: $file is not an absolute path");
    }

    # set fileData (at least, as much as possible)
    my ($user) = getpwuid($UID);
    $this->setFileData('InsertedByUserID', $user);
    $this->setFileData('File', $file);

    # grep possible file types from the database
    my $fileType = $this->getFileType($file);
    $this->setFileData('FileType', $fileType) if defined $fileType;
    
    # if the file is not a minc, then just we've done as much as we can...
    if(!defined($fileType) || $fileType ne 'mnc') {
        return 1;
    }
    
    # get the set of attributes
    my $header = `mincheader -data "$file"`;
    my @attributes = split(/;\n/s, $header);
    foreach my $attribute (@attributes) {
        if($attribute =~ /\s*(\w*:\w+) = (.*)$/s) {
            $this->setParameter($1, $2);
#            fixme debug if ever we run into weird values again
#            if (length($2) < 1000) {
#             #   print length($2)."\n";
#                print "$1\t\t\t---->\t\'" . $this->getParameter($1). "\'\t\n";
#            }
#            end fixme
        }
    }
    # get dimension lengths
    my $dimnames = `mincinfo -dimnames $file`;
    $dimnames = removeWhitespace($dimnames);
    $this->setParameter('dimnames', $dimnames);
    my @dimensions = split(/\s+/, $dimnames);

	 my $dimlength_command = "mincinfo";
    foreach my $dimension (@dimensions) {
		  $dimlength_command .= " -dimlength $dimension";
	 }
	 $dimlength_command .= " $file |";

	 open MI, $dimlength_command or return 0;

	 foreach my $dimension (@dimensions) {
		  my $value = <MI>;
		  chomp($value);
		  $this->setParameter($dimension, $value);
	 }
	 close MI;
    
    $this->setParameter('header', $header);

    return 1;
}

=pod

=head3 setFileData($propertyName, $value)

Sets the fileData property named C<$propertyName> to the value of C<$value>.

INPUTS:
  - $paramName: name of the C<fileData> property
  - $value    : value of the C<fileData> property to be set

=cut

sub setFileData {
    my $this = shift;
    my ($paramName, $value) = @_;
    
    $this->{'fileData'}->{$paramName} = $value;

    if($this->getFileDatum('FileID')) {
	my $fileID = $this->getFileDatum('FileID');
	$value = ${$this->{'dbhr'}}->quote($value);
	
	my $query = "UPDATE files SET $paramName=$value WHERE FileID=$fileID";
	${$this->{'dbhr'}}->do($query);
    }
}

=pod

=head3 setParameter($parameterName, $value)

Sets the parameter named C<$parameterName> to the value of C<$value>.

INPUTS:
  - $paramName: name of the parameter
  - $value    : value of the parameter to be set

=cut

sub setParameter {
    my $this = shift;
    my ($paramName, $value) = @_;
    
    $value = removeWhitespace($value);
    $this->{'parameters'}->{$paramName} = $value;

    if($this->getFileDatum('FileID')) {
	my $fileID = $this->getFileDatum('FileID');
	my $paramID = $this->getParameterTypeID($paramName);
	my $query = "SELECT count(*) AS counter FROM parameter_file WHERE FileID=$fileID AND ParameterTypeID=$paramID";
	my $sth = ${$this->{'dbhr'}}->prepare($query);
	$sth->execute();
	my $row = $sth->fetchrow_hashref();

	$value = ${$this->{'dbhr'}}->quote($value);
	if($row->{'counter'} > 0) {
	    $query = "UPDATE parameter_file SET Value=$value, InsertTime=UNIX_TIMESTAMP() WHERE FileID=$fileID AND ParameterTypeID=$paramID";
	} else {
	    $query = "INSERT INTO parameter_file SET Value=$value, FileID=$fileID, ParameterTypeID=$paramID, InsertTime=UNIX_TIMESTAMP()";
	}
	${$this->{'dbhr'}}->do($query);
    }
}

=pod

=head3 removeParameter($parameterName)

Removes the parameter named C<$parameterName>.

INPUT: name of the parameter to remove

=cut

sub removeParameter {
    my $this = shift;
    my ($paramName) = @_;
    
    undef $this->{'parameters'}->{$paramName};
}

=pod

=head3 getParameterTypeID($parameter)

Gets the C<ParameterTypeID> for the parameter C<$parameter>.  If C<$parameter>
does not exist, it will be created.

INPUT: name of the parameter type

RETURNS: C<ParameterTypeID> (int)

=cut

sub getParameterTypeID {
    my $this = shift;
    my ($paramType) = @_;
    
    my $dbh = ${$this->{'dbhr'}};
    
    # look for an existing parameter type ID
    my $query = "SELECT ParameterTypeID FROM parameter_type WHERE Name=".$dbh->quote($paramType);
    my $sth = $dbh->prepare($query);
    $sth->execute();
    
    if($sth->rows > 0) {
        my $row = $sth->fetchrow_hashref();
        return $row->{'ParameterTypeID'};
    } else {
        # parameter type does not yet exist, so create it
        
        my ($user) = getpwuid($UID);
        $query = "INSERT INTO parameter_type (Name, Type, Description, SourceFrom, Queryable) VALUES (".$dbh->quote($paramType).", 'text', ".$dbh->quote("$paramType magically created by NeuroDB::File").", 'parameter_file', 0)";
        $dbh->do($query);

        # link the inserted ParameterTypeID to a parameter type category
        my $param_type_id = $dbh->{'mysql_insertid'};
        $query = "INSERT INTO parameter_type_category_rel "
                 . " (ParameterTypeID, ParameterTypeCategoryID) "
                 . " SELECT ?, ParameterTypeCategoryID "
                    . " FROM parameter_type_category "
                    . " WHERE Name='MRI Variables'";
        $sth = $dbh->prepare($query);
        $sth->execute($param_type_id);

        return $param_type_id;
    }
}
	

=pod

=head3 removeWhitespace($value)

Removes white space from variable C<$value>.

INPUT: variable to remove white space from (string or array)

RETURNS: string or array of the value without white spaces

=cut
sub removeWhitespace {
    my @vars = @_;
    foreach my $var (@vars) {
        $var =~ s|^\"?\s*||xmgi;
        $var =~ s|\s*\"?\s*$||xmgi; 
# fixme this is garbage
        #$var =~ s|\"?$||xmgi;
        #$var =~ s|\n^\s?||xmgi;
        #$var =~ s|\\n||;
    }

    if(scalar(@vars) == 1) {
        return $vars[0];
    } else {
        return @vars;
    }
}

=pod

=head3 filterParameters

Manipulates the NeuroDB::File object's parameters and removes all parameters of
length > $MAX_DICOM_PARAMETER_LENGTH

=cut
sub filterParameters {
    my $this = shift;

    my $parametersRef = $this->getParameters();

    foreach my $key (keys %{$parametersRef}) {
        if(($key ne 'header') && (defined length($parametersRef->{$key}))
            && (length($parametersRef->{$key}) > MAX_DICOM_PARAMETER_LENGTH)) {
            $this->removeParameter($key);
        }
    }
}

    
1;


__END__

=pod

=head1 TO DO

Other operations should be added: perhaps C<get*> methods for those fields in
the C<files> table which are lookup fields.

Fix comments written as #fixme in the code.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004,2005 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

=head1 AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience


=cut    
