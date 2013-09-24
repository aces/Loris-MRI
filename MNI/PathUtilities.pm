# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::PathUtilities
#@DESCRIPTION: Subroutines for recognizing, parsing, and tweaking POSIX
#              filenames and paths:
#                 split_path
#                 replace_dir
#                 replace_ext
#@EXPORT     : 
#@EXPORT_OK  : normalize_dirs
#              split_path
#              replace_dir
#              replace_ext
#              merge_paths
#              expand_path
#@EXPORT_TAGS: all
#@USES       : 
#@REQUIRES   : Exporter
#              AutoLoader
#@CREATED    : 1997/05/13, Greg Ward (from path_utilities.pl, revision 1.10)
#@MODIFIED   : 
#@VERSION    : $Id: PathUtilities.pm,v 1.10 1997/10/03 13:25:57 greg Rel $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::PathUtilities;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require 5.002;
require Exporter;
require AutoLoader;

@ISA = qw(Exporter);
@EXPORT = ();
@EXPORT_OK = qw(normalize_dirs
                split_path
                replace_dir 
                replace_ext
                merge_paths
                expand_path);
%EXPORT_TAGS = (all => [@EXPORT_OK]);

*AUTOLOAD = \&AutoLoader::AUTOLOAD;

__END__

=head1 NAME

MNI::PathUtilities - recognize, parse, and tweak POSIX file and path names

=head1 SYNOPSIS

   use MNI::PathUtilities qw(:all);

   normalize_dirs ($dir1, $dir2, ...);

   ($dir, $base, $ext) = split_path ($path);
   ($dir, $base, $ext) = split_path ($path, 'first');  # the default
   ($dir, $base, $ext) = split_path ($path, 'last');
   ($dir, $base, $ext) = split_path ($path, 'last', \@skip_ext);
   ($dir, $base) = split_path ($path, 'none');

   @files = replace_dir ($newdir, @files);
   $file = replace_dir ($newdir, $file);

   @files = replace_ext ($newext, @files);
   $file = replace_ext ($newext, $file);

   @dirs = merge_paths (@dirs);

   $path = expand_path ($path) || exit 1;

=head1 DESCRIPTION

F<MNI::PathUtilities> provides a collection of subroutines for doing
common string transformations and matches on Unix/POSIX filenames.  I
use "filenames" here in the generic sense of either a directory name, a
bare filename, or a complete path to a file.  It should be clear from
context what meaning you (or the code) should attach to a given string;
if it's not, that's a documentation bug, so please holler at me.

Throughout this module, directories are usually treated as something to
be directly concatenated onto a bare filename, i.e. they either end with
a slash or are empty.  (The exception is C<merge_paths>, which returns a
list of directories ready to be C<join>'d and stuffed into something
like C<$ENV{'PATH'}>---for this, you want '.' for the current
directory, and no trailing slashes.)  You generally don't have to worry
about doing this for the benefit of the F<MNI::PathUtilities>
subroutines; they use C<normalize_dirs> to take care of it for you.
However, you might want to use C<normalize_dirs> in your own code to
spare yourself the trouble of converting empty strings to '.' and
sticking in slashes.

Error handling is not a worry in this module; the criterion for a
subroutine going in F<MNI::PathUtilities> (as opposed to
F<MNI::FileUtilities>) is that it not explicitly interact with the
filesystem, so there aren't many opportunities for errors to occur.  (But
see C<expand_path> for one routine that does have to worry about error
handling.)

=head1 EXPORTS

By default, F<MNI::PathUtilities> exports no symbols.  You can import in
the usual one-name-at-a-time way like this:

   use MNI::PathUtilities qw(normalize_dirs split_path);

or you can import everything using the C<all> export tag:

   use MNI::PathUtilities qw(:all);

=head1 SUBROUTINES

=over 4

=item normalize_dirs (DIR, ...)

Each DIR (a simple list of strings---no references here) is modified
in-place so that it can be concatenated directly to a filename to form a
complete path.  This just means that we append a slash to each string,
unless it already has a trailing slash or is empty.

For example, the following table shows how C<normalize_dirs> will modify
the contents of a passed-in variable:

   if input value is...           it will become...
   '.'                            './'
   ''                             ''
   '/foo/bar'                     '/foo/bar/'
   '/foo/bar/'                    '/foo/bar/'

If you try to pass a constant string to C<normalize_dirs>, Perl will die
with a "Modification of a read-only value attempted" error message.  So
don't do that.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : normalize_dirs
#@INPUT      : list of directories 
#@OUTPUT     : (arguments modified in place)
#@RETURNS    : 
#@DESCRIPTION: Modifies a list of directory names in place so that they
#              all either end in a slash, or are empty.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1997/05/26, GPW
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub normalize_dirs
{
   # add trailing slash, etc.  -- should replace ensure_trailing_slash
   # (better name, more general)

   foreach (@_)
   {
      $_ .= '/' unless ! defined $_ || $_ eq '' || substr ($_, -1, 1) eq '/';
   }
}


=item split_path (PATH [, EXT_OPT, [SKIP_EXT]])

Splits a Unix/POSIX path into directory, base filename, and extension.
(The extension always starts with some dot after the last slash; which dot
is chosen depends on EXT_OPT and SKIP_EXT.  By default, it splits on the
first dot in the filename.)

C<split_path> is normally called like this:

   ($dir,$base,$ext) = split_path ($path);

If there is no directory (i.e. C<$path> refers implicitly to a file in the
current directory), then C<$dir> will be the empty string.  Otherwise,
C<$dir> will be the head of C<$path> up to and including the last slash.
Usually, you can count on C<split_path> to do the right thing; you should
only have to read the next couple of paragraphs if you're curious about the
exact rules it uses, or if you need to customize how it picks the
extension.

If EXT_OPT is supplied, it must be one of C<'first'>, C<'last'>, or
C<'none'>.  It defaults to C<'first'>, meaning that C<$ext> will start at
the first period after the last slash in PATH, and go the end of the
string.  If EXT_OPT is C<'last'>, then C<$ext> will start at the I<last>
period after the last slash, unless SKIP_EXT is supplied (see below).  If
EXT_OPT is C<'none'>, then C<$ext> will be undefined and any extensions in
C<$path> will be rolled into C<$base>.  Finally, if there are no extensions
at all in PATH, then C<$ext> will be undefined whatever the value of
EXT_OPT.

SKIP_EXT, if supplied, must be a reference to a list of extensions to
ignore when deciding which extension is the last one.  Thus, it only
affects things if EXT_OPT is C<'last'>.  For example, splitting
C<'foo_bar.mnc.gz'> with the "last extension" option would return
C<'foo_bar.mnc'> as the basename, and C<'.gz'> as the extension.  Most
likely, you want C<split_path> to skip over C<'.gz'> while finding the
extension, and treat the dot before C<'mnc.gz'> as the "last" dot.  This
can be done by including C<'gz'> in the SKIP_EXT list:

   ($dir,$base,$ext) = split_path ($path, 'last', [qw(gz z Z)]);

This works by repeatedly attempting to strip off a trailing C</\.(gz|z|Z)/>
from PATH before searching for the "last dot" to find the extension.  After
the remaining extension is extracted, the "skipped" extensions are appended
to it in order to preserve the entire original pathname.  This method can
be used to parse C<'foo.bar.pgp.gz'> or C<'foo.bar.gz.pgp'>, assuming that
both C<'pgp'> and C<'gz'> are in the SKIP_EXT list (in any order).

(Note that even though the return value C<$ext> includes a leading dot,
you should not put leading dots on the extensions in SKIP_EXT.  The idea
is to maximize your convenience on both ends: it is easiest to type a
list of extensions without dots, and including a dot on the output side
means you can reconstruct the original path by just concatenating the
three return values.)

Finally, C<$base> is just the portion of C<$path> left after pulling off
C<$dir> and C<$ext>---i.e., from the last slash to the first period (if
C<EXT_OPT> is C<'first'>), or from the last slash to the last period
excluding skipped extensions (if C<EXT_OPT> is C<'last'>).

For example, 

   split_path ($path)

will split the C<$path>s in the right-hand column into the lists shown on
the left:

   'foo.c'                      ('', 'foo', '.c')
   '/unix'                      ('/', 'unix', undef)
   '/bin/ls'                    ('/bin/', 'ls', undef)
   '/foo/bar/zap.mnc'           ('/foo/bar/', 'zap', '.mnc')
   '/foo/bar/zap.mnc.gz'        ('/foo/bar/', 'zap', '.mnc.gz')

However, if you called it with an EXT_OPT of C<'last'>:

   split_path ($path, 'last')

then the last example would be split differently, like this:

   '/foo/bar/zap.mnc.gz'        ('/foo/bar/', 'zap.mnc', '.gz')

But if you add a SPLIT_EXT list to that example:

   split_path ($path, 'last', [qw(gz z Z)])

then we return to the original split:

   '/foo/bar/zap.mnc.gz'        ('/foo/bar/', 'zap, '.mnc'.gz')

If the filename, however, had been something like C<'ding.dong.mnc.gz'>,
where you want to treat C<'ding.dong'> as the basename, then you would
have to use an EXT_OPT of C<'last'> with a SPLIT_EXT list.  (Despite
this convention being at odds with most of the Unix world, it appears to
have some currency.)

Finally, with an EXT_OPT of C<'none'>, filenames with extensions would
be split like this:

   'foo.c'                      ('', 'foo.c', undef)
   '/foo/bar/zap.mnc'           ('/foo/bar/', 'zap.mnc', undef)
   '/foo/bar/zap.mnc.gz'        ('/foo/bar/', 'zap.mnc.gz', undef)

Note that a "missing directory" becomes the empty string, whereas a
"missing extension" becomes C<undef>.  This is not a bug; my rationale is
that every path has a directory component that may be empty, but a missing
extension means there really is no extension.

See L<File::Basename> for an alternate solution to this problem.
C<File::Basename> is not specific to Unix paths, usually results in
nicer looking code (you don't have to do things like
C<(split_path($path))[1]> to get the basename), and is part of the
standard Perl library; however, it doesn't deal with file extensions in
quite so flexible and generic a way as C<split_path>.

=cut

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


=item replace_dir (NEWDIR, FILE, ...)

Replaces the directory component of each FILE with NEWDIR.  You can supply
as many FILE arguments as you like; they are I<not> modified in place.
NEWDIR is first "normalized" so that it ends in a trailing slash (unless it
is empty), so you don't have to worry about doing this yourself.
(C<replace_dir> does not modify its NEWDIR parameter, though, so you might
want to normalize it yourself if you're going to use it for other
purposes.)

Returns the list of modified filenames; or, in a scalar context, returns
the first element of that list.  (That way you can say either 
C<@f = replace_dir ($dir, @f)> or C<$f = replace_dir ($dir, $f)> without
worrying too much about context.)

For example,

   @f = replace_dir ('/tmp', '/foo/bar/baz', 'blam', '../bong')

sets C<@f> to C<('/tmp/baz', '/tmp/blam', '/tmp/bong')>, and 

   $f = replace_dir ('/tmp', '/foo/bar/baz')

sets C<$f> to C<'/tmp/baz'>.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : replace_dir
#@INPUT      : $newpath - directory to replace existing directories with
#              @files   - list of files to have directories replaced
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Replaces the directory component of a list of pathnames.
#              Returns the list of files with substitutions performed.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/04, Greg Ward
#@MODIFIED   : 1995/05/23, GW: renamed to &ReplaceDir
#-----------------------------------------------------------------------------
sub replace_dir
{
   my ($newpath, @files) = @_;

   normalize_dirs ($newpath);
   foreach (@files)
   {
      # Try to substitute an existing directory (ie. eat greedily up to
      # a slash) with the new directory.  If that fails, then there's no
      # slash in the filename, so just jam the new directory on the front.

      s|.*/|$newpath| 
         or $_ = $newpath . $_;
   }
   wantarray ? @files : $files[0];
}


=item replace_ext (NEWEXT, FILE, ...)

Replaces the final extension (whatever follows the last dot) of each FILE
with NEWEXT.  You can supply as many FILE arguments as you like; they are
I<not> modified in place.

Returns the list of modified filenames; or, in a scalar context, returns
the first element of that list.  (That way you can say either 
C<@f = replace_ext ($ext, @f)> or C<$f = replace_dir ($ext, $f)> without
worrying too much about context.

For example,

   replace_ext ('xfm', 'blow_joe_mri.mnc')

in a scalar context returns C<'blow_joe_mri.xfm'>; in an array context, it
would just return the one-element list C<('blow_joe_mri.xfm')>.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : replace_ext
#@INPUT      : $newext  - extension to replace existing extensions with
#              @files   - list of files to have extensions replaced
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Replaces the final extension (whatever follows the final dot)
#              of a list of pathnames.  Returns the list of files with
#              substitutions performed in array context, or the first filename
#              from the list in a scalar context.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/23, Greg Ward (from &ReplaceDir)
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub replace_ext
{
   my ($newext, @files) = @_;

   foreach (@files)
   {
      s/\.[^\.]*$/\.$newext/;           # replace existing extension
   }
   wantarray ? @files : $files[0];
}


=item merge_paths (DIRS)

Goes through a list of directories, culling duplicates and converting
them to a form more amenable to stuffing in PATH variables and the like.
Basically, this means undoing the work of C<normalize_path>: trailing
slashes are stripped, and empty strings are replaced by '.'.

Returns the input list with duplicates removed (after those minor string
transformations).

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &merge_paths
#@INPUT      : a list of directories (well, they could almost be any strings,
#              except we tweak 'em a bit with the assumption that they are
#              directories for a PATH-like list)
#@OUTPUT     : 
#@RETURNS    : the input list, but with duplicates removed, trailing slashes
#              stripped, and empty strings converted to '.'
#@DESCRIPTION: 
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/12/04 GPW
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub merge_paths
{
   my (@dirs) = @_;
   my (%seen, $dir, @path);

   foreach $dir (@dirs)
   {
      $dir =~ s|/$|| unless $dir eq '/'; # strip trailing slash
      $dir = '.' unless $dir;           # ensure no empty strings
      push (@path, $dir) unless $seen{$dir};
      $seen{$dir} = 1;
   }
   @path;
}


=item expand_path (PATH)

Expands user home directories (using the ~ notation) and environment
variables (using the $ notation) in a path.  

Home directories are expanded as follows: if PATH starts with a tilde (~),
the text from the tilde to the first slash or end of string (if no slashes)
is taken to be a username.  If this username is empty (ie. PATH is just
C<'~'> or starts with C<'~/'>), then the tilde is replaced by the current
user's home directory (from C<$ENV{'HOME'}>).  Otherwise, the username is
looked up in the password file to find that user's home directory, which
then replaces the leading C<'~username'> in PATH.  If the username is
unknown, C<expand_path> prints a warning and returns false.

Environment variables are expanded as follows: any $ seen in PATH
followed by a string of one or more letters, digits, and underscores is
replaced by the environment variable named by that string.  If no such
variable is found, C<expand_path> prints a warning and returns false.

Note that the first call to C<expand_path> that expands a home directory
other than that of the current user will involve a slight delay as the
entire password file is read in.  This information is cached for future
invocations, though.

=cut

my $dir_cache;

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &expand_path
#@INPUT      : $path
#@OUTPUT     : 
#@RETURNS    : $path, with ~name and $var expanded
#@DESCRIPTION: Expands usernames and environment variables in a path.
#@CREATED    : 1997/07/29, GPW
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub expand_path
{
   my ($path) = @_;
   my ($homedir, $username);

   if ($path =~ s|^~([^/]*)||)          # starts with a twiddle
   {
      $username = $1;
      if ($username eq '')              # empty string -- current user
      {
         $path = $ENV{'HOME'} . $path;
      }
      else                              # some other user
      {
         unless (defined $dir_cache)
         {
            my (@pwent);
            $dir_cache->{$pwent[0]} = $pwent[7]
               while (@pwent = getpwent);
            endpwent;
         }

         unless (exists $dir_cache->{$username})
         {
            warn "unknown username \"$username\"\n";
            return 0;
         }

         $path = $dir_cache->{$username} . $path;
      }
   }

   # and now expand any environment variables in $path

   while ($path =~ s|\$(\w+)|$ENV{$1}|e)
   {
      unless (exists $ENV{$1})
      {
         warn "unknown environment variable \"$1\"\n";
         return 0;
      }
   }

   return $path;

}  # expand_path

=back

=head1 AUTHOR

Greg Ward, <greg@bic.mni.mcgill.ca>.

=head1 COPYRIGHT

Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

This file is part of the MNI Perl Library.  It is free software, and may be
distributed under the same terms as Perl itself.

=cut

1;
