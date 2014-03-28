# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 251 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/volume_min.al)"
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

# end of MNI::MincUtilities::volume_min
1;
