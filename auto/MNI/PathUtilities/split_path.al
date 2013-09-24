# NOTE: Derived from blib/lib/MNI/PathUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::PathUtilities;

#line 284 "blib/lib/MNI/PathUtilities.pm (autosplit into blib/lib/auto/MNI/PathUtilities/split_path.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &split_path
#@INPUT      : $path    - a Unix path specifiction (optional directory + file)
#              $ext_opt - specifies how to deal with file extensions:
#                         if "none", extension is ignored and returned as
#                           part of the base filename
#                         if "first", the *first* dot in a filename denotes
#                           the extension, eg ".mnc.gz" would be an extension
#                         if "last", the *last* dot denotes the extension,
#                           eg. just ".gz" would be the extension
#                         the default is "first"
#@OUTPUT     : 
#@RETURNS    : array: ($dir, $base, $ext)
#@DESCRIPTION: Splits a Unix path specification into directory, base file 
#              name, and extension.  (The extension is chosen based on
#              either the first or last dot in the filename, depending
#              on the $ext_opt argument; by default, it splits on the 
#              first dot in the filename.)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/10, Greg Ward - taken from mritotal and modified
#@MODIFIED   : 1995/08/10, GW: added $ext_opt option to handle splitting off
#                              the extension in different ways
#              1997/02/26, GW: changed to preserve trailing slash and 
#                              empty directory string
#              1997/05/29, GW: added fallback so 'last' option works on a 
#                              path with no extension
#-----------------------------------------------------------------------------
sub split_path
{
   my ($path, $ext_opt, $skip_ext) = @_;
   my ($dir, $base, $ext);
   
   $ext_opt = "first" unless defined $ext_opt;
   
   # If filename has no extension, don't try to act as though it does
   # (both "last" and "first" options assume there is an extension
   
   #    $ext_opt = "none" if $path !~ m+/?[^/]*\.+;
   
   if ($ext_opt eq "none")
   {
      ($dir, $base) = $path =~ m+^(.*/)?([^/]*)$+;
   } 
   elsif ($ext_opt eq "first")
   {
      ($dir, $base, $ext) = $path =~ m+^(.*/)?([^/\.]*)(\..*)?$+;
   }
   elsif ($ext_opt eq "last")
   {
      my $trailer = '';
      if ($skip_ext)
      {
         my $skip_re = '\.(' . join ('|', @$skip_ext) . ')';
         $trailer = $1 . $trailer while $path =~ s/($skip_re)$//;
      }

      ($dir, $base, $ext) = $path =~ m+^(.*/)?([^/]*)(\.[^/.]*)$+
         or ($dir, $base) = $path =~ m+^(.*/)?([^/]*)$+;

      if ($trailer)
      {
         $ext ? ($ext .= $trailer) : ($ext = $trailer);
      }
   }
   else
   {
      die "split_path: unknown extension option \"$ext_opt\"\n";
   }
   
   $dir = "" unless ($dir);
   
   ($dir, $base, $ext);
}

# end of MNI::PathUtilities::split_path
1;
