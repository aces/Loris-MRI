use warnings;
use strict;

package NeuroDB::MincUtilities;

use File::Basename;

=pod

=head3 modify_header($argument, $value, $minc, $awk)

Runs C<minc_modify_header> and insert MINC header information if not already
inserted.

INPUTS:
  - $argument: argument to be inserted in minc header
  - $value   : value of the argument to be inserted in minc header
  - $minc    : minc file
  - $awk     : awk information to check if argument not already inserted
               in the MINC header

RETURNS: 1 if argument was indeed inserted into the minc file, undef otherwise

=cut
sub modify_header {
    my ( $argument, $value, $minc, $awk ) = @_;

    # check if header information not already in MINC file
    my $hdr_val = fetch_header_info( $argument, $minc, $awk );

    # insert MINC header unless the field was already inserted and
    # its header value equals the value to insert
    my  $cmd = "minc_modify_header -sinsert $argument=$value $minc";
    system($cmd) unless ( ($hdr_val) && ($value eq $hdr_val) );

    # check if header information was indeed inserted in minc file
    my $hdr_val2 = fetch_header_info( $argument, $minc, $awk );

    return $hdr_val2;
}




=pod

=head3 fetch_header_info($field, $minc, $awk, $keep_semicolon)

Fetches header information in a MINC file.

INPUTS:
  - $field: field to look for in minc header
  - $minc : minc file
  - $awk  : awk information to check if argument not already inserted in
            the MINC header
  - $keep_semicolon: if defined, keep semicolon at the end of the
                     extracted value

RETURNS: field value found in the MINC header

=cut
sub fetch_header_info {
    my ( $field, $minc, $awk, $keep_semicolon ) = @_;

    my $value;

    my $cmd = "mincheader " . $minc
        . " | grep "  . $field
        . " | awk '{print $awk}' "
        . " | tr '\n' ' ' ";

    my $val = `$cmd`;
    $value = $val if ( $val !~ /^\s*"*\s*"*\s*$/ );

    if ($value) {
        $value =~ s/^\s+//; # remove leading spaces
        $value =~ s/\s+$//; # remove trailing spaces
        # remove ";" unless $keep_semicolon is defined
        $value =~ s/;// unless ( $keep_semicolon );
    }

    return $value;
}




=pod

=head3 ecat2minc($ecat_file)

Converts ECAT files into MINC format (unless the MINC file already exists and
is readable by the user running the script).

INPUT: path to the ECAT file

RETURNS: path to the MINC file if it exists, undef otherwise

=cut

sub ecat2minc {
    my ($ecat_file) = @_;

    # check if there is a MINC file associated to the ECAT file
    my $dirname = dirname($ecat_file);
    my $minc_file = $dirname . "/" . basename($ecat_file, '.v') . ".mnc";
    unless ( -e $minc_file ) {
        # create the MINC file unless it already exists.
        my $ecat2mnc_cmd = "ecattominc -quiet "
            . $ecat_file . " "
            . $minc_file;
        system($ecat2mnc_cmd);
    }

    return undef unless ( -r $minc_file );
    return $minc_file;
}


1;