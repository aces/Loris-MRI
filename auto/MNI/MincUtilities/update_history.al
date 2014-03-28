# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 489 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/update_history.al)"
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

# end of MNI::MincUtilities::update_history
1;
