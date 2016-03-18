# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 341 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/check_output_path.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &check_output_path
#@INPUT      : $path   - path to a file or directory
#@OUTPUT     : 
#@RETURNS    : 0 if any component of $path is not a directory (or
#                cannot be created as one), or if last directory component
#                isn't a writeable directory (or can't be created).
#              1 otherwise
#@DESCRIPTION: If $path is a file (ie. doesn't end with a slash), ensures
#              that conditions are optimal for creating it.  If $path
#              is a directory, ensures that it exists and is writeable.
#
#              In detail, splits a file path up and makes sure that every
#              directory component except the last is indeed a directory,
#              or can be created as one.  Makes sure that the last
#              component before a slash (last directory) is both a
#              directory and writeable; if not, attempts to create it.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1996/03/14, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub check_output_path
{
   my ($path) = @_;
   my (@dirs, $dir, $partial, $last_dir);

   # Split $path up by directory.  We always pop off the last element,
   # because it's either empty ($path looks like /foo/bar/ -- it's meant to
   # be a directory), or is the filename component ($path looks
   # /foo/bar/baz, so /foo/bar/ is the directory and we ignore baz)

   @dirs = split ('/', $path, -1);
   pop @dirs;                           # strip non-directory component

   if (@dirs == 0)                      # no dirs left -- $path is 'foo',
   {                                    # ie. a file relative to current dir
      $last_dir = '.';
      $partial = '';
   }
   elsif (@dirs == 1)                   # $path either '/foo' or 'foo/bar',
   {                                    # so we have ('') or ('foo') in @dirs
      $last_dir = pop @dirs;            # this empties @dirs
      $partial = ($last_dir eq '')
         ? '/'                          # absolute path -- last dir really '/'
         : '';                          # relative path -- last dir just 'foo'
   }
   else
   {
      $last_dir = pop @dirs;            # get the last directory for separate
                                        # checking (must exist & be writeable)
      $partial = ($dirs[0] eq '')       # absolute path? (ie. '/foo/bar/...')
         ? '/'                          # then start at root
         : ''                           # else ('foo/bar/...') start right here
   }

#   print "path     = $path\n";
#   print "last_dir = $last_dir\n";
#   print "dirs     = (" . join (',', @dirs) . ")\n";
#   print "partial  = \"$partial\"\n";

   # Check all but the last directory component: each must be a directory.

   for $dir (@dirs)
   {
      $partial .= "$dir";
#      print "checking: $partial\n";

      # If $partial doesn't exist (dangling links count as "exist" in this
      # case), then try to create it.  If the mkdir fails, then we fail.

      if (! (-e $partial || -l $partial))
      {
	 unless (mkdir ($partial, 0770))
	 {
	    warn "\"$path\" not a writeable path: couldn't create \"$partial\": $!\n";
	    return 0;
	 }
      }

      # $partial does exist, but it's not a directory -- fail

      elsif (! -d $partial)
      {
	 warn "\"$path\" not a writeable path: \"$partial\" is not a directory\n";
	 return 0;
      }

      # $partial exists and is a directory, so continue on to the next
      # element of @dirs.  Note that we don't check for writeability,
      # because it doesn't matter yet -- only the last directory 
      # has to be writeable, so it's handled separately.

      $partial .= '/' unless $partial eq '/';
   }

   # Now check the last directory; must be a directory and writeable.

   $partial .= $last_dir;
#   print "checking: $partial (last dir)\n";

   if (! (-e $partial || -l $partial))
   {
      unless (mkdir ($partial, 0770))
      {
	 warn "\"$path\" not a writeable path: couldn't create \"$partial\": $!\n";
	 return 0;
      }
   }
   elsif (! (-d $partial && -w $partial))
   {
      warn "\"$partial\" not a writeable directory\n";
      return 0;
   }

   return 1;
}

# end of MNI::FileUtilities::check_output_path
1;
