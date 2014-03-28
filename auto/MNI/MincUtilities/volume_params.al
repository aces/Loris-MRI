# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 624 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/volume_params.al)"
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

# end of MNI::MincUtilities::volume_params
1;
