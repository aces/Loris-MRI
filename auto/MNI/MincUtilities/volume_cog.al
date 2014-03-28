# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 584 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/volume_cog.al)"
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

# end of MNI::MincUtilities::volume_cog
1;
