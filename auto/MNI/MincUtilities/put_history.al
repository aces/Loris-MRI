# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 423 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/put_history.al)"
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

# end of MNI::MincUtilities::put_history
1;
