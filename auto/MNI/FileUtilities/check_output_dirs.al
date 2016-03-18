# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 223 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/check_output_dirs.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : check_output_dirs
#@INPUT      : @dirs - list of directories to check
#@OUTPUT     : 
#@RETURNS    : true if all directories exist and are writeable, *or* were
#                 successfully created
#              false otherwise
#@DESCRIPTION: Checks that each directory in a list of directories either
#              exists and is writeable; *or* creates it.
#
#              Prints a meaningful error message and returns false if any
#              of @dirs 1) exist but aren't directories, 2) exist but
#              aren't writeable, or 3) don't exist and can't be created.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/02, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub check_output_dirs
{
   my (@dirs) = @_;

   my $num_err = 0;
   my $dir;

   foreach $dir (@dirs)
   {
      next unless $dir;		# skip blank strings
      if (-e $dir || -l $dir)   # file exists (or is dangling link)
      {
	 if (! -d $dir)         # but *not* a directory
	 {
	    warn "$dir already exists but is not a directory\n";
	    $num_err++;
	 }
	 elsif (! -w $dir)      # is a directory, but not writeable
	 {
	    warn "$dir is a directory but not writeable\n";
	    $num_err++;
	 }
      }
      else                      # no file, no dangling link
      {
	 if (! mkdir ($dir, 0770))
	 {
	    warn "couldn't create \"$dir\": $!\n";
	    $num_err++;
	 }
      }
   }
   return ($num_err == 0);
}

# end of MNI::FileUtilities::check_output_dirs
1;
