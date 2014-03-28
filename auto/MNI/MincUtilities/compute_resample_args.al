# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 845 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/compute_resample_args.al)"
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

# end of MNI::MincUtilities::compute_resample_args
1;
