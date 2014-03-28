# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 276 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/volume_max.al)"
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

# end of MNI::MincUtilities::volume_max
1;
