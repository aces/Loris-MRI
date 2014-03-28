# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 376 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/get_history.al)"
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

# end of MNI::MincUtilities::get_history
1;
