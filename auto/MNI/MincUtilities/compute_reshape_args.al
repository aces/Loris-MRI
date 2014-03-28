# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 904 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/compute_reshape_args.al)"
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

1;
1;
# end of MNI::MincUtilities::compute_reshape_args
