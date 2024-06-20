# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::MincUtilities
#@DESCRIPTION: various MINC hacks, most using external programs
#@EXPORT     : 
#@EXPORT_OK  : volume_min volume_max volume_minmax
#              percent_threshold auto_threshold volume_cog
#              get_history put_history update_history
#              volume_params get_dimension_order
#              compute_resample_args compute_reshape_args
#@EXPORT_TAGS: range, threshold, history, geometry, args, all
#@USES       : MNI::Spawn, MNI::NumericUtilities, MNI::MiscUtilities
#@REQUIRES   : Exporter
#@CREATED    : 1997/08/07, Greg Ward (from minc_utilities.pl, revision 1.16)
#@MODIFIED   : 
#@VERSION    : $Id: MincUtilities.pm,v 1.9 2007/09/14 19:03:40 claude Exp $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::MincUtilities;

use strict;
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS
            $Execute $Spawner);

require 5.002;
require Exporter;
require AutoLoader;

use Carp;

use MNI::Spawn;
use MNI::NumericUtilities qw(round);
use MNI::MiscUtilities qw(userstamp timestamp shellquote);

@ISA = qw(Exporter);
@EXPORT_OK = qw(volume_min volume_max volume_minmax
                percent_threshold auto_threshold volume_cog
                get_history put_history update_history
                volume_params get_dimension_order
                compute_resample_args compute_reshape_args);

%EXPORT_TAGS = (range    => [qw(volume_min volume_max volume_minmax)],
                threshold=> [qw(percent_threshold auto_threshold)],
                history  => [qw(get_history put_history update_history)],
                geometry => [qw(volume_cog volume_params get_dimension_order)],
                args     => [qw(compute_resample_args
                                compute_reshape_args)],
                all      => \@EXPORT_OK);

*AUTOLOAD = \&AutoLoader::AUTOLOAD;

$Spawner = new MNI::Spawn (verbose => 0,
                           execute => undef,
                           strict  => 0,
                           search  => 0);

if (! defined $main::Execute)
{
   warn "MNI::MincUtilities: warning: \$main::Execute not defined " .
        "(assuming true) -- did you use MNI::Startup?\n";
   $main::Execute = 1;
}
*Execute = \$main::Execute;

__END__

=head1 NAME

MNI::MincUtilities - various MINC file hacks using external utilities

=head1 SYNOPSIS

   use MNI::MincUtilities qw(:range);
   $min = volume_min ($vol);
   $max = volume_max ($vol);
   ($min, $max) = volume_minmax ($vol);

   use MNI::MincUtilities qw(:threshold);
   $threshold = percent_threshold ($min, $max, $percent);
   $threshold = auto_threshold ($vol);

   use MNI::MincUtilities qw(:history);
   @history = get_history ($vol);
   put_history ($vol, @history);
   update_history ($vol [, $replace [, $history]]);

   use MNI::MincUtilities qw(:geometry);
   $cog = volume_cog ($vol);
   volume_params ($vol, \@start, \@step, \@length, \@dir_cosines, \@dims);
   ($order, $permutation) = get_dimension_order ($vol);

   use MNI::MincUtilities qw(:args);
   @resample_args = compute_resample_args (\@start, \@extent, \@step);
   @reshape_args = compute_reshape_args (\@order, \@oldstart, \@oldstep,
                                         \@start, \@extent, \@step);

=head1 DESCRIPTION

F<MNI::MincUtilities> provides a number of miscellaneous utility routines
to query and/or compute various useful parameters of a MINC file and the
data in it, and to get/put/update its history.  The common thread is that
everything (well, almost everything) is done via external utilities, such
as C<mincinfo> or C<volume_stats>.  Note that some of these utilities are
distributed with the MINC package, so if you have the MINC library
installed you should have the utilities; other utilities are distributed
with other packages (such as C<volume_cog>, included with the MNI AutoReg
package); and other utilities (such as C<volume_stats>) may not be
available outside the MNI.  Unfortunately, there's currently no way to know
which is which until you try to use them via a function in
F<MNI::MincUtilities> and your program crashes.

Eventually, this module will (hopefully) be superseded by the F<MNI::MINC>
family of modules, but since those modules don't exist as of this writing,
F<MNI::MincUtilities> is being provided as a stop-gap measure.  It is
intended that this will solve the problem of reliance on possibly
unavailable external programs.

The subroutines provided by F<MNI::MincUtilities> fall into roughly five
groups:

=over 4

=item * volume range 

Query the volume min and max values (C<volume_min>, C<volume_max>,
C<volume_minmax>).

=item * compute thresholds

Compute either percentage or automatic threshold values
(C<percent_threshold>, C<auto_threshold>).

=item * get/put/update history

Get or replace the entire history attribute (C<get_history>,
C<put_history>), or update it with a record of the current execution
(C<update_history>).

=item * volume geometry

Query or compute volume sampling parameters and geometrical statistics
(C<volume_cog>, C<volume_params>, C<get_dimension_order>).

=item * generate argument lists

Generate argument lists for C<mincresample> or C<mincreshape> based on
desired sampling parameters for a volume (C<compute_resample_args>,
C<compute_reshape_args>).

=back

=head1 EXPORTS

By default, F<MNI::MincUtilities> exports no symbols.  You can import in
the usual one-name-at-a-time way like this:

   use MNI::MincUtilities qw(volume_min volume_params);

which works fine if you're only using a few routines.  This quickly gets
cumbersome in large programs that use lots of routines, though, so the
module provides a couple of "export tags" to let you specify subroutines
by group.  The tags correspond to the groups of subroutines described
above; they are:

=over 4

=item C<range>

=item C<threshold>

=item C<history>

=item C<geometry>

=item C<args>

=back

For example, to import the names of all the volume range functions:

   use MNI::MincUtilities qw(:range);

Finally, an C<all> tag is provided to import all exportable symbols.

=head1 EXECUTION CONTROL

In order to cooperate better with other programs and modules,
F<MNI::MincUtilities> makes an effort to respect the global C<$Execute>
variable, and not to actually do much of anything if it is false.  If you
use F<MNI::Startup> before F<MNI::MincUtilities>, you shouldn't have any
problems: F<MNI::Startup> will set its C<$Execute> global to true, and
export it into your main program.  Then, when F<MNI::MincUtilities> is
compiled, C<$main::Execute> will already be available for it to use.  In
fact, the routines in F<MNI::MincUtilities> will always use
C<$main::Execute>, so you can change it at will (or the caller of your
program can change it with the C<-execute> command-line option), and
F<MNI::MincUtilities> will either execute commands or not, depending on
C<$main::Execute>.

However, if you choose not to C<use MNI::Startup>, you'll have to define
C<$main::Execute> before compiling F<MNI::MincUtilities>, like this:

   BEGIN { $Execute = 1; }
   use MNI::MincUtilities;

If you don't have the creation of C<$Execute> in a C<BEGIN> block before
you C<use MNI::MincUtilities>, then a warning will be printed and
C<$main::Execute> will be defined for you (and set to 1).

The point of all this, in case you were wondering, is to allow your
program to operate in a "dry run" mode that runs no external programs
and depends on no temporary (or other) files.  This is very useful for a
"sanity check" pass, to make sure that a complicated program will do
just what you expect it to do without strange failures, rather than
running for several hours and then failing.  (Of course, it doesn't
protect you from everything---just from silly logic errors that you
catch by reading any information echoed by the program, or from mistakes
in your Perl code that would crash the script.)  The routines in
F<MNI::MincUtilities> not only avoid executing programs or depending on
the existence of files, they also return dummy values that you can
safely use in any further computations without fear of "uninitialized
value" warnings.  Generally, any numeric values (such as thresholds,
coordinates, and most sampling parameters) are returned as zero when
C<$main::Execute> is false.  The exceptions are direction cosines, the
dimension list (both returned by C<volume_params>), and
order/permutation vectors (returned by C<get_dimension_order>).  These
are all returned in a "canonical form", namely (1,0,0,0,1,0,0,0,1) for
the direction cosines, (C<xspace>, C<yspace>, C<zspace>) for the
dimension list, and (0,1,2) for order and permutation vectors.  (See
C<volume_params> and C<get_dimension_order> for more information on this
arcana.)

=head1 SUBROUTINES

=head2 Volume range

=over 4

=item volume_min (VOLUME)

Gets the alleged volume minimum (from the C<image-min> variable).  This
may not be reliable, depending on the software that wrote VOLUME.

=cut

sub volume_min
{
   my ($volume) = @_;

   my ($status, @image_min, $volmin);
   
   if ($Execute)
   {
      $Spawner->spawn (['mincinfo', '-varvalue', 'image-min', $volume],
                       stdout => \@image_min);
      $volmin = (sort { $a <=> $b } @image_min)[0];
   }
   else { $volmin = 0; }

   $volmin;
}


=item volume_min (VOLUME)

Gets the alleged volume maximum (from the C<image-max> variable).  This
may not be reliable, depending on the software that wrote VOLUME.

=cut

sub volume_max
{
   my ($volume) = @_;

   my ($status, @image_max, $volmax);
   
   if ($Execute)
   {
      $Spawner->spawn (['mincinfo', '-varvalue', 'image-max', $volume],
                       stdout => \@image_max);
      $volmax = (sort { $a <=> $b } @image_max)[-1];
   }
   else { $volmax = 0; }

   $volmax;
}


=item volume_minmax (VOLUME)

Calls C<volume_min> and C<volume_max> and returns their results (in that
order) as a two element list.  Again, this is of dubious reliability.

=cut

sub volume_minmax
{
   my ($volume) = @_;
   my ($status, $volmax, $volmin);

   (volume_min ($volume), volume_max ($volume));
}


=back

=head2 Compute thresholds

=over 4

=item percent_threshold (MIN, MAX, PERCENT)

Computes the value that is PERCENT of the way between MIN and MAX.  PERCENT
should be a fraction in the range 0..1; MIN and MAX can be any numbers you
like, but they will most likely be the minimum and maximum real-world
values from some MINC file.  (This function doesn't actually do anything
with any MINC file, it just does arithmetic---for that reason, it probably
belongs in F<MNI::NumericUtilities> rather than F<MNI::MincUtilities>.
Thus, it may be moved without warning at some point in the future---be
warned!)

=cut

sub percent_threshold
{
   my ($volmin, $volmax, $percent) = @_;
   ($volmax - $volmin) * $percent + $volmin;
}


=item auto_threshold (VOLUME)

Computes an automatic background threshold (using C<volume_stats>
C<-biModalT>.  The threshold is returned as a real-world value.

=cut

sub auto_threshold
{
   my ($volume) = @_;

   my $threshold;
   if ($Execute)
   {
      $Spawner->spawn (['volume_stats', '-biModalT', '-quiet', $volume],
                       stdout => \$threshold);
      chop $threshold;
   }
   else { $threshold = 0; }

   $threshold;
}


=back

=head2 Get/put/update history

=over 4

=item get_history (VOLUME)

Fetches the global C<history> attribute from a MINC file, and splits it on
newline into a list of strings.  Since C<history> attributes always end in
a newline, this results in an empty string at the end of the list;
C<get_history> removes this empty string for you, and returns the resulting
list.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &get_history
#@INPUT      : $volume
#@OUTPUT     : 
#@RETURNS    : list containing all the elements from the MINC file
#@DESCRIPTION: Fetches the global "history" attribute from a MINC file,
#              splits it on newlines, and returns the list resulting
#              from that split.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Nov 1995, Greg Ward (originally in get_flipped_volume)
#@MODIFIED   : 1997/08/07, GPW: changed to use spawn
#-----------------------------------------------------------------------------
sub get_history
{
   my ($volume) = @_;
   my (@cmd, @history);

   return () unless $Execute;

   @cmd = qw(mincinfo -error_string "" -attvalue :history);
   $Spawner->spawn ([@cmd, $volume], stdout => \@history);
   pop @history if $history[-1] eq '';
   @history;
}

=item put_history (VOLUME, HISTORY)

Joins HISTORY (a list of strings, not an array ref) with newlines,
appends a trailing newline, and puts the resulting string into the
global C<history> attribute of the MINC file named by VOLUME.  Using
C<get_history> and C<put_history>, it's quite easy to add your own line
to a C<history> attribute:

   @history = get_history ($vol);
   push (@history, "this is my history line");
   put_history ($vol, @history);

or even:

   put_history ($vol, get_history ($vol), "this is my history line");

However, it's even easier if you use C<update_history> (see below).

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &put_history
#@INPUT      : $volume
#              @history
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Joins the @history array with newlines, and puts the 
#              resulting string into a MINC file as the global history
#              attribute.  (This completely replaces the existing
#              history; if you wish to update it, see &update_history).
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Nov 1995, Greg Ward (originally in get_flipped_volume)
#@MODIFIED   : 1997/08/07, GPW: changed to use spawn
#-----------------------------------------------------------------------------
sub put_history
{
   my ($volume, @history) = @_;
   my ($history);

   return unless $Execute;
   $history = join ("\n", @history) . "\n";
   $Spawner->spawn (['minc_modify_header', $volume, '-sinsert', 
                     ":history=$history"]);
}


=item update_history (VOLUME [, REPLACE [, HISTORY]])

Fetches, updates, and replaces the C<history> global attribute from the
MINC file named by VOLUME.

REPLACE is an integer that tells how many entries to lop off the end of
the history list before appending a new entry.  This is useful if your
program runs a known number of external utilities, each of which
contributes one line to the history, in producing its output file.  You
could use REPLACE to drop the lines contributed by those external
utilities, so that running your program results in just one line being
added.  For example:

   Spawn (['mincresample', $invol, $tempvol, @resample_args]);
   Spawn (['mincreshape', $tempvol, $outvol, @reshape_args]);

   update_history ($outvol, 2);

would result in one history line being added to C<$tempvol>, and another to
C<$outvol>.  Thus, we ask C<update_history> to remove both of these lines
from C<$outvol>, and replace them with the history line for your program.
If REPLACE is not supplied, it defaults to zero, meaning not to remove any
previous history lines.

HISTORY, if supplied, should be a string that is appended directly to the
history list---thus, you can completely cook up a history line.  If HISTORY
is not supplied (or undefined, or an empty string), then C<update_history>
will create a history line for you.  This line will contain an exhaustive
summary of your program's execution environment, including the name of the
user running the program, the host, the current working directory at
program startup (from C<$MNI::Startup::StartDir>), the date and time at
program startup (from C<$^T>), the program name (C<$0>) and its complete
argument list (C<@ARGV>).  (This is yet another good reason why you
shouldn't clobber C<$0> and C<@ARGV>; the F<MNI::Startup> and
F<Getopt::Tabular> modules together make it easy to avoid this no-no.)

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &update_history
#@INPUT      : $volume  - name of MINC file to update
#              $replace - number of items to delete from the history list
#                 before adding the new one.  If not given or zero,
#                 no items are removed.
#              $history - entry to add to history; can be either:
#                   - non-empty string: $history is copied into the MINC
#                     file's history attribute with no changes or additions
#                   - empty or undefined (ie. a "false" value): 
#                     same as if you pass an array ref [$0 @ARGV] (so
#                     passing an array ref is really if you want something
#                     *other* than [$0 @ARGV], ie. if -- for whatever
#                     nefarious reason -- you wish to lie about your 
#                     program's name and arguments
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Adds an item to the global history attribute in a MINC file.
#              Optionally deletes other items from the end of the list
#              first, allowing you to (eg., if $replace == 1) replace
#              the last item with your desired item.  This is useful for
#              Perl scripts that are front-ends for a known number of
#              operations by standard MINC tools, each of which results
#              in a single history item.  
#
#              Note: if a timestamp is generated, it will be the time at
#              which the script began running, rather than the current time.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &get_history, &put_history
#              &userstamp, &timestamp
#@CREATED    : 1996/05/29, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub update_history
{
   my ($volume, $replace, $history) = @_;

   return unless $Execute;

   # First figure out the real history line: either the caller supplied the
   # whole thing ($history is a non-empty string), or they supplied a list
   # with the program name and arguments ($history is an array ref), or
   # they want us to cook it up entirely ($history is a false value)

   if (defined $history && $history ne '' && !ref $history)
   {
      # do nothing -- put $history right into the MINC file
   }
   elsif (! $history)
   {
      unless (defined $MNI::Startup::StartDir)
      {
         carp "update_history: warning: \$MNI::Startup::StartDir not defined ".
              "(did you remember to use MNI::Startup?)";
         $MNI::Startup::StartDir = '???';
      }
      $history = sprintf ("[%s] [%s] %s %s", 
                          userstamp (undef, undef, $MNI::Startup::StartDir), 
                          timestamp ($^T), 
                          $0, shellquote (@ARGV));
   }
   else
   {
      croak "update_history: \$history must be a string or nothing";
   }

   # Now fetch the existing history attribute

   my @orig_history = get_history ($volume);

   # Remove the last $replace items (if $replace was supplied)

   splice (@orig_history, -$replace) if (defined $replace && $replace > 0);

   # Put $history onto the list, and write it to the MINC file

   push (@orig_history, $history);
   put_history ($volume, @orig_history);
}  # update_history


=back

=head2 Volume geometry

=over 4

=item volume_cog (VOLUME)

Computes the "centre of gravity" of a volume using C<volume_cog>.  This is
returned as a three-element array (x,y,z).

=cut

sub volume_cog
{
   my ($volume) = @_;
   my (@cog);

   if ($Execute)
   {
      my @out;
      $Spawner->spawn (['volume_cog', $volume], stdout => \@out);
      @cog = split (' ', $out[-1]);
   }
   else
   {
      @cog = (0, 0, 0);
   }

   @cog;
}


=item volume_params (VOLUME, START, STEP, LENGTH, DIRCOS, DIMS)

Gets all the sampling parameters for a MINC file and stuffs them into
arrays that you supply by reference.  All of the arguments except VOLUME
should be array references or undefined; if an argument is undefined,
obviously you won't be able to get at the sampling parameters it
represents.

The arrays referenced by START, STEP, and LENGTH will each be replaced
with three-element arrays containing the respective sampling parameter
in I<(x,y,z)> order; DIRCOS's array will become a nine-element array
with the direction cosines vectors for I<x>, I<y>, and I<z>
respectively; and DIMS' array will be replaced with a list of three
strings naming the three spatial dimensions in the file.

The behaviour of C<volume_params> on a file with less than three spatial
dimensions is undefined.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : volume_params
#@INPUT      : $volume - file to query
#              $start  - reference to list to fill with starts
#              $step   - reference to list to fill with step sizes
#              $length - reference to list to fill with dimension lengths
#              $dircos - reference to list to fill with direction cosines
#              $dims   - reference to list to fill with dimension names
#              (If any of these "references" are just false values, then
#              they won't be followed -- that way you can specify "undef"
#              for values you're not interested in.)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Gets the x, y, and z starts, steps, and lengths for a
#              MINC volume.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 95/04/21, Greg Ward
#@MODIFIED   : 95/08/04, GW: simplified to handle negative steps and extents
#              95/08/16, GW: changed to GetVolumeParams and made so it returns
#                            all three interesting spatial parameters
#              95/08/30, GW: renamed to volume_params and moved from autocrop
#                            to minc_utilities.pl
#              96/02/12, GW: converted to use Perl 5 references
#                            added direction cosines stuff
#              97/04/07, GW: added $dims to get dimension names
#              97/08/07, GW: changed to use spawn
#-----------------------------------------------------------------------------
sub volume_params
{
   my ($volume, $start, $step, $length, $dircos, $dims) = @_;
   my (@cmd, $output, @output);

   @cmd = qw(mincinfo -error_string 0
             -attval xspace:start -attval yspace:start -attval zspace:start
             -attval xspace:step -attval yspace:step -attval zspace:step
             -dimlength xspace -dimlength yspace -dimlength zspace
             -attval xspace:direction_cosines
             -attval yspace:direction_cosines
             -attval zspace:direction_cosines
             -dimnames);
   push (@cmd, $volume);

   if ($Execute)
   {
      $Spawner->spawn (\@cmd, stdout => \@output);
      grep (s/ ( ^ \s+ ) | ( \s+ $ ) //xg, @output);
   }
   else
   {
      @output = (map (0, 0..11), 'xspace yspace zspace');
   }

   @$start = @output[0..2] if $start;
   @$step = @output[3..5] if $step;
   @$length = @output[6..8] if $length;
   if ($dircos)
   {
      @$dircos = (1,0,0, 0,1,0, 0,0,1);
      my $i;
      for $i (0,1,2)
      {
	 my ($base) = $i * 3;

	 @$dircos[$base .. $base+2] = split (/\s+/, $output[9+$i])
	    unless ($output[9+$i] eq "0");
      }
   }
     
   @$dims = split (' ', $output[12]) if $dims;
}  # volume_params


=item get_dimension_order (VOLUME)

Computes the dimension order and permutation for a MINC file.  These are
two vectors that are very useful when you need to go back and forth
between the canonical dimension ordering I<(x,y,z)> and whatever order
the dimensions happen to be in in a particular MINC file.

The dimension order vector is the easy one: order[I<i>] tells you which
dimension is the I<i>'th dimension of your volume.  For instance, a
coronal volume has dimensions I<(y,z,x)>; its order vector is (1,2,0), a
simple transcription of I<(y,z,x)> to numerical form.  (Put another way,
order[0]==1 means that dimension 0 of the file is canonical dimension 1,
or yspace.)

The permutation vector is a little trickier to wrap your head around,
even though in a way it's just the "inverse" of the order vector.  In
short, perm[I<i>] is where to find the I<i>'th canonical dimension in
your file's dimension list.  Going with the coronal example again, the
permutation vector is (2,0,1): looking up canonical dimension 2 (zspace)
in perm[] gives 1, and indeed zspace is at slot 1 in the list of
dimensions (counting from zero, of course).

The main reason that these two are so confusing is that they're usually
the same---the reason I've used the coronal ordering as an example here
is that it's the only standard ordering where the order and permutation
vectors are different!  (Of the 6 possible orders for three dimensions,
only coronal I<(y,z,x)> and the non-standard order I<(z,x,y)> have
different order and permutation vectors.)  However, to be truly general,
you have to know when to use which one.

In short: use the order vector when you have something in I<(x,y,z)>
order and want it in volume order; use the permutation vector to go from
volume to I<(x,y,z)> order.  This is particular easy in Perl using array
slices.  Say you have a list of parameters in I<(x,y,z)> order (such as
the lists filled in by C<volume_params>):

     @count = ($x_count, $y_count, $z_count);

that you want in volume order (say, for use with C<mincreshape>).  Again
assuming a coronal volume, the order vector is (1,2,0), and so

     @count_v = @count[@order]
              = @count[1,2,0] 
              = ($y_count, $z_count, $x_count)

which of course is in coronal order.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &get_dimension_order
#@INPUT      : $volume - name of MINC file to get dimension names from; 
#                   OR - reference to an array containing the dim names
#@OUTPUT     : 
#@RETURNS    : $order  - ref to dimension order list
#              $perm   - ref to dimension permutation list
#@DESCRIPTION: Computes the dimension order and permutation for a MINC
#              file.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : mincinfo
#@CREATED    : 1996/10/22, GW (from code formerly in autocrop)
#@MODIFIED   : 
#@COMMENTS   : The "order" and "permutation" jargon is entirely my
#                 own invention; I don't know if anybody else uses
#                 the same terms.  Helps me get a grip on this damn 
#                 stuff, at any rate.
#              Shouldn't actually bomb on volumes with < 3 spatial 
#                 dimensions (or with non-spatial dimensions; they will
#                 just be ignored).  However, I really don't know if
#                 it produces useful results in those cases.
#-----------------------------------------------------------------------------
sub get_dimension_order
{
   my ($volume) = @_;
   my (@dimlist, %dim_num, @order, @perm);

   %dim_num = ('xspace', 0, 'yspace', 1, 'zspace', 2);

   if ($volume && ! ref $volume)        # it's a string -- name of MINC file
   {
      my $dimlist;
      if ($Execute)
      {
         ### this fails in minc2.
         ###  $Spawner->spawn (['mincinfo', '-dimnames', $volume],
         ### this will work in minc2.
         $Spawner->spawn (['mincinfo', '-vardims', 'image', $volume],
                          stdout => \$dimlist);
         chop $dimlist;
         @dimlist = split (/\s+/, $dimlist);
      }
      else
      {
         @dimlist = qw(xspace yspace zspace);
      }
   }
   elsif (ref $volume eq 'ARRAY')
   {
      @dimlist = @$volume;
   }
   else
   {
      croak "get_dimension_order: \$volume must be either a string or " .
            "an array ref";
   }

   @dimlist = grep (/^[xyz]space$/, @dimlist);

   my ($i, $dim_num);
   for $i (0 .. $#dimlist)
   {
      $dim_num = $dim_num{$dimlist[$i]};
      $order[$i] = $dim_num;
      $perm[$dim_num] = $i;
   }

   (\@order, \@perm);
}


=back

=head2 Generate argument lists

=over 4

=item compute_resample_args (START, EXTENT, STEP)

Computes a list of arguments for C<mincresample> based on the sampling
parameters implied by START, EXTENT, and STEP (all references to
three-element lists).  START and STEP should just contain the C<start> and
C<step> attributes for the three spatial dimensions, in I<(x,y,z)> order.
EXTENT should describe the spatial extent of each dimension; it is
basically the same as the dimension length in a NetCDF file, except that it
is a real-world (not voxel) measurement and can be negative for dimensions
sampled in "reverse order" (with respect to the MINC standard).  In fact,
EXTENT[I<i>] must be negative if STEP[I<i>] is.

C<compute_resample_args> simply computes the dimension lengths (number
of samples) by dividing EXTENT by STEP and rounding up, and then puts
everything together with C<-start>, C<-step>, and C<-nelements> options.
A list containing all these options, suitable for popping into a
C<mincresample> command list, is returned.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : compute_resample_args
#@INPUT      : @$start  - start (world) (x,y,z) coordinates for resampling
#              @$extent - extent (length in mm) of each dimension (x,y,z)
#              @$step   - step (in mm) of each dimension (x,y,z)
#@OUTPUT     : 
#@RETURNS    : @params - mincresample command line options needed to
#                        carry out the bounding specified by @start and
#                        @extent, with steps specified by @step
#@DESCRIPTION: Computes the needed dimension lengths to accomodate the
#              desired step and extent, and generates appropriate
#              parameters for mincresample (-start, -step, -nelements)
#              to carry out the volume bounding.
#
#              Does nothing about direction cosines, -like, or
#              -use_input_sampling -- that's up to the caller to figure out.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 95/04/21, Greg Ward
#@MODIFIED   : 96/10/21, GW: changed to use Perl5 ref's and my
#              96/10/22, GW: changed name (from StudlyCaps to lower_case)
#                            and moved from autocrop into minc_utilities.pl
#              97/08/08, GW: changed to return an argument list, not a string
#@COMMENTS   : What should we do about direction cosines?!?!?!?
#-----------------------------------------------------------------------------
sub compute_resample_args
{
   my ($start, $extent, $step) = @_;
   my (@length, $i);

   foreach $i (0,1,2)
   {
      $length[$i] = round ($extent->[$i] / $step->[$i], 1, +1);
   }

   ('-start', @$start, '-step', @$step, '-nelements', @length);
}  


=item compute_reshape_args (ORDER, OLDSTART, OLDSTEP, START, EXTENT, STEP)

Computes the parameters necessary for C<mincreshape> to give a volume a
new spatial extent as described by START and EXTENT (both references to
three-element arrays in I<(x,y,z)> order).  If OLDSTART and START differ
by anything other than integral multiples of STEP (or OLDSTEP), then
only approximate bounds will be computed.  The results are thrown
together as C<-start> and C<-count> options for C<mincreshape>, and
returned as a list.

ORDER should be the dimension order vector that will apply to the I<new>
file; all the other vectors are in I<(x,y,z)> order, so it's not
necessary to supply the order vector of the old file.  If you are
changing the dimension order, it's still your responsibility to put the
appropriate option (C<-coronal>, C<-transverse>, etc.) on the
C<mincreshape> command line.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &compute_reshape_args
#@INPUT      : @$order    - the dimension order vector, as returned by
#                           &get_dimension_order
#              @$oldstart - the current `start' parameters of the volume
#                           to be reshaped
#              @$oldstep  - the current `step' parameters of the volume
#                           to be reshaped
#              @$start    - the desired new `start' parameters (after
#                           reshaping)
#              @$extent   - the desired new extent of each dimension in mm
#              @$step     - the desired new step (may differ from @$oldstep
#                           in sign only!)
#@OUTPUT     : 
#@RETURNS    : @params    - parameters for mincreshape, as
#                           ('-start', xstart, ystart, zstart, 
#                            '-count', xcount, ycount, zcount)
#@DESCRIPTION: Computes the parameters necessary for mincreshape to
#              give a volume a new spatial extent as described by @$start
#              and @$extent.  If @$oldstart and @$start differ by anything
#              other than integral multiples of @$step (or @$oldstep),
#              then it will only approximate the desired bounds.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &round (from numeric_utilities.pl)
#@CREATED    : 95/06/25, Greg Ward
#@MODIFIED   : 95/08/18, GW: fixed so it would work
#              95/10/01, GW: fixed finding of vstart 
#              96/10/21, GW: changed to use Perl5 ref's and my
#              96/10/22, GW: changed name (from StudlyCaps to lower_case)
#                            and moved from autocrop into minc_utilities.pl;
#                            changed to take the dimension order as a 
#                            parameter rather than computing it here
#              97/08/08, GW: changed to return an argument list, not a string
#-----------------------------------------------------------------------------
sub compute_reshape_args
{
   my ($order, $oldstart, $oldstep, $start, $extent, $step) = @_;
   my (@perm, @vstart, @count, $i);

   foreach $i (0 .. 2)
   {
      $vstart[$i] = round (($start->[$i] - $oldstart->[$i]) / $oldstep->[$i]);
      $count[$i] = round ($extent->[$i] / $step->[$i], 1, +1);
      $count[$i] = -$count[$i] if ($step->[$i] == -$oldstep->[$i]);
   }
   @vstart = @vstart[@$order];
   @count = @count[@$order];

   ('-start', join (',', @vstart), '-count', join (',', @count));
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
