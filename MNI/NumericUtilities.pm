# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::NumericUtilities
#@DESCRIPTION: Short routines for doing common numeric tasks.
#@EXPORT     : 
#@EXPORT_OK  : in_range
#              labs
#              round
#              min
#              max
#@EXPORT_TAGS: all
#@USES       : 
#@REQUIRES   : Exporter
#@CREATED    : 1997/06/06, Greg Ward (from numeric_utilities.pl, revision 1.9)
#@MODIFIED   : 
#@VERSION    : $Id: NumericUtilities.pm,v 1.3 1997/10/03 13:37:23 greg Rel $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::NumericUtilities;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require 5.002;
require Exporter;
require AutoLoader;

use Carp;
use POSIX qw(floor ceil);

@ISA = qw(Exporter);
@EXPORT = ();
@EXPORT_OK = qw(in_range labs round);
%EXPORT_TAGS = (all => \@EXPORT_OK);

*AUTOLOAD = \&AutoLoader::AUTOLOAD;

__END__

=head1 NAME

MNI::NumericUtilities - common trivial numeric operations

=head1 SYNOPSIS

   use MNI::NumericUtilities qw(:all);

   in_range ($val, $lo, $hi);

   @abs_values = labs (@values);

   $rounded = round ($value [, $factor [, $dir]]);

=head1 DESCRIPTION

F<MNI::NumericUtilities> provides a handful of common trivial numeric
operations.  About the only thing these routines have in common is 
a tendency to assume that all scalars are floating-point numbers.

=head1 SUBROUTINES

=over 4

=item in_range (VAL, LO, HI)

Tests whether VAL is in the closed interval [LO,HI].  Returns -1 if VAL
is less than LO, +1 if VAL is greater than HI, 0 otherwise.  Note the
C<cmp>-like backwards logic: a false value means that VAL is in range.
(I could be persuaded to consider this a bug and fix it, but you'd
better ask soon.)

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : in_range
#@INPUT      : $val - value to test
#              $lo  - lower bound
#              $hi  - upper bound
#@OUTPUT     : 
#@RETURNS    : 0 if $val is within the closed interval [$lo, $hi]
#              -1 if $val is less than $lo
#              +1 if $val is greater than $hi
#@DESCRIPTION: Tests whether a number is within a specified range.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 95/3/8, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub in_range
{
   my ($val, $lo, $hi) = @_;

   croak "invalid range: LO must be less than or equal to HI" 
      unless $lo <= $hi;
   return (-1) if ($val < $lo);
   return (+1) if ($val > $hi);
   return (0);
}


=item labs (VALS)

Computes and returns the absolute values of a list of values.  VALS
should be a simple list, not a reference to anything.  Returns the whole
list of absolute values in an array context, or just the first one in a
scalar context.  (Thus, C<labs ($val)> is the same as C<abs ($val)>,
but slower.)

Note that Perl's built-in C<abs> function only works on and returns
scalars.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &labs
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Returns the absolute value of its argument(s).  In an array
#              context, returns a list of absolute values, otherwise just
#              a scalar.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 95/04/12, GW
#@MODIFIED   : 95/09/01, GW: fixed so it doesn't modify its arguments (dohh!)
#              97/04/11, GW: renamed to labs (list absolute value), and
#                            made it call Perl's builtin abs function
#@COMMENTS   : You might think this was obsolete with Perl 5, but
#              the Perl 5 builtin only takes a scalar -- this version
#              will take and return a list if desired.
#-----------------------------------------------------------------------------
sub labs
{
   my (@nums) = @_;

   foreach (@nums)
   {
      $_ = abs $_;
   }
   wantarray ? @nums : $nums[0];
}


=item round (VAL [, FACTOR [, DIR]])

Rounds VAL towards some multiple of FACTOR (which defaults to 1).  If DIR
is -1, it rounds down to the next lowest multiple of FACTOR; if DIR is 0,
it rounds to the nearest multiple of FACTOR, if DIR is +1, it rounds up to
the next highest multiple of FACTOR.  The default is to round to the
nearest multiple of FACTOR.

For example:

   round (3.25)        == 3
   round (3.25, 5)     == 5
   round (3.25, 5, -1) == 0
   round (-1.2, 2, +1) == 0
   round (-1.2, 2)     == -2

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &round
#@INPUT      : $value - number to round
#              $factor - what to round to; eg. 1 to round to an integer,
#                        .5 to round to a half-integer, or 10 to a
#                        factor of 10.
#              $direction - 0 to round to nearest $factor
#                          -1 to round down to next $factor
#                          +1 to round up to next $factor
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Round off a number to a factor of
#              $factor, where $factor is the first argument.  Round either
#              to the nearest factor, or down, or up, depending on the value
#              of $direction.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 95/05/03, Greg Ward (hacked from Alex Zijdenbos' code)
#@MODIFIED   : 95/08/07, GW: added $direction
#              96/10/21, GW: changed "0" to "0.0" in comparison (!?!??!!!?)
#-----------------------------------------------------------------------------
sub round
{
   my($value, $factor, $direction) = @_;
   $factor = 1 unless defined $factor;
   $direction = 0 unless defined $direction;

   $factor = abs ($factor);
   $value /= $factor;
   if ($direction == 0)
   {
      $value += ($value < 0.0) ? (-0.5) : (+0.5);
      $value = int($value) * $factor;
   }
   elsif ($direction == -1)
   {
      $value = floor ($value) * $factor;
   }
   elsif ($direction == +1)
   {
      $value = ceil ($value) * $factor;
   }
}


=back

=head1 AUTHOR

Greg Ward, <greg@bic.mni.mcgill.ca>.

=head1 COPYRIGHT

Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

This file is part of the MNI Perl Library.  It is free software, and may be
distributed under the same terms as Perl itself.

=cut

1;
