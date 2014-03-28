# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 343 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/auto_threshold.al)"
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

# end of MNI::MincUtilities::auto_threshold
1;
