# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::FileUtilities
#@DESCRIPTION: Functions to manipulate/check/validate/search files and
#              directories on POSIX systems.
#@EXPORT     : check_output_dirs
#              check_output_path
#              check_input_dirs
#              check_files
#              test_file
#@EXPORT_OK  : search_directories
#              find_program
#              find_programs
#              generate_numbered_filename
#              statfs
#@EXPORT_TAGS: all, check, search, misc
#@USES       : POSIX, MNI::PathUtilities
#@REQUIRES   : Exporter
#@CREATED    : 1997/04/25, Greg Ward (from file_utilities.pl, revision 1.16)
#@MODIFIED   : 
#@VERSION    : $Id: FileUtilities.pm,v 1.13 1999/11/30 17:11:11 crisco Exp $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::FileUtilities;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require 5.002;
require Exporter;
require AutoLoader;

use Carp;
use POSIX qw(strftime);

use MNI::PathUtilities qw(normalize_dirs);

@ISA = qw(Exporter);
@EXPORT = ();
@EXPORT_OK = qw(check_output_dirs
                check_output_path
                check_input_dirs
                check_files
                test_file
                search_directories
                find_program
                find_programs
                generate_numbered_filename
                statfs);
%EXPORT_TAGS = (all    => [@EXPORT_OK],
                check  => [qw(check_output_dirs
                              check_output_path
                              check_input_dirs
                              check_files
                              test_file)],
                search => [qw(search_directories
                              find_program
                              find_programs)],
                misc   => [qw(generate_numbered_filename
                              statfs)]);

*AUTOLOAD = \&AutoLoader::AUTOLOAD;

__END__                                 # everything after here is autoloaded

=head1 NAME

MNI::FileUtilities - manipulate/check/validate/search files and directories

=head1 SYNOPSIS

   use MNI::FileUtilities qw(:check);
   check_output_dirs (@dirs) || exit 1;
   check_output_path ($path) || exit 1;
   check_input_dirs (@dirs) || exit 1;
   $file = test_file ($test, $file) || die "couldn't find $file\n";
   check_files (@files) || exit 1;

   use MNI::FileUtilities qw(:search);
   $dir = search_directories ($file, \@search_dirs [, $test]) 
      || die "couldn't find $file\n";
   $program = find_program ($program [, \@path]) || exit 1;
   (@programs = find_programs (\@programs [, \@path])) || exit 1;

   use MNI::FileUtilities qw(:misc);
   $file = generate_numbered_filename ($base, $ext [, $add_date]);
   ($type, $blocksize, $blocks, $blocksfree, $files, $ffree) = 
      statfs ($path);

=head1 DESCRIPTION

F<MNI::FileUtilities> provides a loosely-related collection of utility
subroutines for performing various common operations that help maximize
your program's likelihood of running successfully and provide thorough
diagnostics when things go wrong.  The module is rife with assumptions that
it's running under a POSIX-compliant operating system (i.e. Unix and
Unix-like systems such as Linux), so using it under another OS will be
dodgy at best.

The subroutines fall roughly into the following groups:

=over 4

=item checking/testing

Check that files or directories exist and are writeable/readable (as
appropriate): C<check_output_dirs>, C<check_output_path>,
C<check_input_dirs>, C<check_files>, C<test_file>.

=item searching

Search for file(s) across a list of directories: C<search_directories>,
C<find_program>, C<find_programs>.

=item miscellaneous

C<generate_numbered_filename>, C<statfs>.

=back

=head1 EXPORTS

By default, F<MNI::FileUtilities> exports no symbols.  You can import in
the usual one-name-at-a-time way like this:

   use MNI::FileUtilities qw(check_output_dirs test_file);

which works fine if you're only using a few routines.  This quickly gets
cumbersome in large programs that use lots of routines, though, so the
module provides a couple of "export tags" to let you specify subroutines
by group.  The tags are:

=over 4

=item C<check>

C<check_output_dirs>, C<check_output_path>, C<check_input_dirs>,
C<check_files>, and C<test_file>

=item C<search>

C<search_directories>,  C<find_program>, and C<find_programs>

=item C<misc>

C<generate_numbered_filename> and C<statfs>

=back

For example, to import the names of all the file/directory checking
subroutines:

   use MNI::FileUtilities qw(:check);

Finally, an C<all> tag is provided to import all exportable symbols.

=head1 ERROR HANDLING

Error handling is fairly consistent: in general, the routines here print a
warning and return false when they discover an error.  The guiding
principle is to tell the user as much as he/she needs to know; all you (the
programmer using F<MNI::FileUtilities>) have to do is know when to pay
attention to the return values from F<MNI::FileUtilities> routines, and
what to do when they fail.  In most cases, you should pay attention to the
return value; usually, you will want to bomb (e.g. C<exit 1>) as soon as an
error is reported.  I've deliberately left this choice up to you (rather
than having the subroutines C<die> on any error), because there are
situations where you might want to blunder on ahead.

If for any reason you need to capture the warning message, rather than
have it printed to C<STDERR>, you can set C<$SIG{'__WARN__'}>.  See
L<perlvar> for more information.

There are a few routines that will C<die> on failure.  Generally, if you
mess up by supplying bad arguments, the F<MNI::FileUtilities> routines will
C<die> or C<croak>.  If blundering on in the face of error would cause
serious problems for future invocations of a routine, it will C<die>
(C<generate_numbered filename> is the only one that falls in this
category).  Finally, if you ask a routine for the impossible, it will
C<die>.  (The only instance of this currently is calling C<statfs> on an
architecture other than Linux/x86 or IRIX.)

That said, the documentation below should mention the error handling
behaviour for every individual subroutine.  If any such information is
missing, that's a documentation bug---please tell me!  Also, the
calling summaries in the synopsis above implicitly tell you the
preferred way for dealing with errors from each subroutine.

=head1 SUBROUTINES

=head2 Checking/testing routines

=over 4

=item check_output_dirs (DIRS)

DIRS should be a list of directories to check; C<check_output_dirs>
ensures that each element of the list is a writeable directory, and
attempts to create (with C<mkdir>) those that are not.  Note that
C<check_output_dirs> will not attempt to create more than one level of
directory; if you try to check F</foo/bar/baz>, and only F</foo> exists,
it will not try to create both F</bar> and F<baz>.  You should be using
C<check_output_path> if you require that behaviour.

If any elements of DIRS are false (e.g., undefined or the empty string),
they are silently skipped.

Prints a complete and self-sufficient warning for every error found.  Note
that if one element of the list fails, it will keep trying with the others.
Returns true if every element of the list was successfully tested or
created; false if there were any errors at all.

Possible errors are: 1) already exists, but isn't a directory, 2) is
a directory but not writeable, and 3) C<mkdir> fails.

=cut

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


=item check_output_path (PATH)

If PATH is a filename (doesn't end with a slash), C<check_output_path>
ensures that conditions are optimal for creating it.  (That is, it
treats everything up to the last slash in PATH as a directory, and
attempts to create that directory a little more vigorously than
C<check_output_dirs>.  In particular, it will create as many levels of
directories as are needed to ensure that PATH can be written to.)

If PATH ends with a slash, then it is assume to be a directory with no
filename component, and the same applies---C<check_output_path>
attempts to create as many levels of directory as are needed to bring
PATH into existence as a writeable directory.

Prints a comprehensive warning and returns false if any errors occur.
Possible errors are: 1) C<mkdir> fails at any level; 2) some `directory' in
PATH exists, but isn't actually a directory; and 3) the final component of
PATH exists and is a directory, but isn't writeable.

The reasoning behind the trailing slash business is as follows: PATH can
be either a file that you will need to create, or a directory in which
you will create several files.  A trailing slash is just used to tell
C<check_output_dirs> that this is indeed a directory you're interested
in.

For example, you might be about to create a file F</tmp/mydir/tmpfile>.
To maximize your chances of success, you want to be sure that
F</tmp/mydir> exists, is a directory, and is writeable by you.  Either
C<check_output_dirs> or C<check_output_path> can help you with this, but
in slightly different ways.

If all you have (and care about) is a filename, it's usually more
convenient to use C<check_output_path>; for example,

   $file = '/tmp/mydir/tmpfile';
   check_output_path ($file) || exit 1;

ensures that conditions are optimal for creating C<$file>.  If it fails,
you're not going to be able to create C<$file>, so you may as well give
up before even trying to open the file.  No error message is necessary
because C<check_output_path> prints a clear and detailed warning before
returning.

However, if you're carrying around a directory name and using it to
generate filenames, you can usually get away with using
C<check_output_dirs>.  For example:

   $dir = '/tmp/mydir';
   check_output_dirs ($dir) || exit 1;

Note that if you passed C<$dir> without a trailing slash to
C<check_output_path> it would merely ensure that conditions are optimal
for creating F</tmp/mydir>---probably not what you want.  

The main drawback to C<check_output_dirs> is that it will only create
one level of directory; C<check_output_path>'s main flaw is that you can
only check one path at a time.  Furthermore, its logic is quite a bit
more complicated and prone to subtle bugs---but I think I've got that
one licked.

=cut


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


=item check_input_dirs (DIRS)

DIRS should be a list of directories to check.  Each item in the list is
checked to make sure it exists, is a directory, and is both readable and
executable.  Prints a comprehensive warning message for any directory
that doesn't meet all these conditions.  Returns true if all directories
in DIRS are ok, false if there were any errors.  Any element of DIRS may
be false (undefined or the empty string), and it will be silently
skipped.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : check_input_dirs
#@INPUT      : @dirs - list of directories to check
#@OUTPUT     : 
#@RETURNS    : 1 if all directories exist and are readable
#              0 otherwise
#@DESCRIPTION: Checks to see if all desired input directories exist and
#              are readable and executable.  Prints meaningful error 
#              messages and returns false if anything is wrong.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/02, Greg Ward
#@MODIFIED   : 1997/05/01, GW: added "-x" condition
#-----------------------------------------------------------------------------
sub check_input_dirs
{
   my (@dirs) = @_;
   my ($num_err) = 0;
   my $dir;

   foreach $dir (@dirs)
   {
      next unless $dir;                 # skip blank strings
      if (-e $dir || -l $dir)
      {
	 if (! -d $dir)
	 {
	    warn "$dir exists but is not a directory\n";
	    $num_err++;
	 }
	 elsif (! (-r $dir && -x $dir))
	 {
	    warn "$dir is a directory, but is not readable/searchable\n";
	    $num_err++;
	 }
      }
      else
      {
	 warn "directory $dir does not exist\n";
	 $num_err++;
      }
   }
   return ($num_err == 0);   
}


=item check_files (FILES [, VARIANTS])

FILES should be a list of files to check.  (It must be an array ref if
the optional argument VARIANTS is supplied; otherwise, FILES can just be
an array using up the whole argument list to C<check_files>.  This is
just a hack for backwards compatibility, though; new code should pass an
array ref for FILES.)  Each item in the list is checked to make sure it
exists, is a regular file (or a symlink to one), and is readable.  Any
element of FILES may be false (undefined or the empty string), and it
will be silently skipped.

VARIANTS can be used to make C<check_files> check several variations on
each filename.  This is done by calling C<test_file>; see below for
details on its operation.  The easiest way to use this feature is to
pass a true scalar value in as VARIANTS; this will just use
C<test_file>'s default list of extensions, which (conveniently enough)
is C<('gz','z','Z')>.  If you need to use a different list of
extensions, make VARIANTS a reference to a list of those extensions
(without dots, just like C<test_file>).  If VARIANTS is not supplied or
is false, then just the filenames passed in as FILES will be tested.

In a scalar context, returns true if all files in FILES are ok, false if
there were any errors.  Thus, the following is a common idiom:

   ($infile1, $infile2) = @ARGV;
   check_files ($infile1, $infile2) || exit 1;

It's OK to fail silently since C<check_files> prints ample
warnings in case of any error.  Note that you should check that C<@ARGV>
has the number of elements you expect before doing this, as
C<check_files> silently skips any members of FILES that are
undefined.  (Yes, this is a feature.)

In an array context, returns the list of found files.  This list will
have the same length as the FILES list that you pass in, but any files
that weren't found will be replaced with C<undef>.  This is most useful
when used in conjunction with the variant-extensions feature, e.g. you
could do something like this

   ($infile1, $infile2) = check_files (\@ARGV, 1);
   exit 1 unless $infile1 && $infile2;

to pull filenames from the command line, make sure each one exists
(possibly in compressed form), and fail silently if any weren't found in
any form.  Again, it's OK to fail silently, and again, you should check
the length of C<@ARGV> before doing this.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : check_files
#@INPUT      : @files - a list of filenames to check for readability
#@OUTPUT     : 
#@RETURNS    : 1 if all files exist and are readable
#              0 otherwise (and prints a warning for every bad file)
#@DESCRIPTION: Makes sure that each of a list of files exists and is readable.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Aug 1994, Greg Ward
#@MODIFIED   : 1995/04/25, GW: gave it two possible error messages
#              1995/10/30, GW: changed so it warns and returns 0 instead 
#                              of dying
#              1997/05/02, GW: added $variants argument and trickery
#                              with files as array or array ref for
#                              backwards compatiblity
#-----------------------------------------------------------------------------
sub check_files
{
   my ($files, $variants) = @_;
   my @files;
   if (ref $files)
   {
      @files = @$files;
   }
   else
   {
      @files = @_;
      undef $variants;
   }
   my ($num_err, $new, @ok_files);

   # what $variants can be:
   #   1) array ref -- passed to test_file as is
   #   2) any other true value -- converted to undef so test_file
   #      will use default list of variant extensions
   #   3) any false value (including undefined) -- don't test variants 
   #      at all ie. pass a defined false value to test_file)

   $variants = 0 if ! $variants;
   undef $variants if $variants && ! (ref $variants eq 'ARRAY');
   croak "check_files: \$variants must be an array ref or a simple scalar"
      if (ref $variants && ref $variants ne 'ARRAY');

   $num_err = 0;
   local $_;
   foreach (@files)
   {
      next unless $_;
      $new = test_file ('-e', $_, $variants);

      if ($new)                         # the file at least exists
      {
         if (! -f $new)                 # ... but it isn't a regular file
         {
            warn "$new not a regular file\n";
            $num_err++;
            undef $new;
         }
         elsif (! -r $new)              # exists, is regular file, but is
         {                              # unreadable
            warn "$new not readable\n";
            $num_err++;
            undef $new;
         }

         push (@ok_files, $new);
      }
      else                              # file doesn't exist at all
      {	
         my $is_link = ($variants ? test_file ('-l', $_, $variants) : -l);
         if ($is_link)
         {
            warn "$_ is a dangling link (file does not exist)\n";
         }
         else
         {
            warn "$_ does not exist\n";
         }

	 $num_err++;
         push (@ok_files, undef);
      }
   }

   wantarray 
      ? return @ok_files
      : return ($num_err == 0);
}


=item test_file (TEST, FILE [, VARIANTS])

C<test_file> performs a file test (or tests) on FILE, as well as on
variations of FILE if necessary.  VARIANTS is a list of extensions which
are used to generate the variant filenames; it defaults to
C<['gz','z','Z']>---this is convenient for testing a filename that
might exist in either original form or compressed form.  You could pass
in a different list of variant extensions to look for other variations
on a file, e.g. C<['pgp']> to look for an encrypted variant.

TEST is a string containing some Perl expression which evaluates to true
or false depending on the value of C<$_>.  The most common use is a
single file test operator such as C<-e>; you could also use a boolean
combination of file test operators, such as C<-e && (-f || -l) && -x> to
test that FILE (or one of its variants) exists, is a regular file or
symlink, and is executable.

VARIANTS could be an array ref (as implied above), where the array is a
list of filename extensions with no leading dot.  Or, it could be a
false scalar value, meaning not to test any variations in FILE (this is
the same as passing a reference to an empty list, but possibly more
convenient in some circumstances).  Finally, if VARIANTS is undefined or
not supplied, it defaults to C<['gz','z','Z']>.

Returns the filename that ultimately passes TEST, or a false value if no
passing filename is found.  Dies with a useful error message if you pass
in bogus arguments.

The exact modus operandi is as follows: TEST is C<eval>'d with C<$_> set
to FILE.  If this returns true, FILE is returned.  Then, the variant
filenames are tried out (this step is skipped if VARIANTS is an empty
list or false).  First, C<test_file> attempts to strip off any variant
extension already on FILE, and tests the resulting base filename.  If
this succeeds, the base filename is returned.  If an extension was
stripped, but the base filename failed the test, then C<test_file> fails
and returns false.  Finally, each possible variant extension is appended
to FILE (with an intervening dot), and the resulting filename is tested.  As
soon as a passing filename is found, it is returned.  If no passing
filename is found, C<test_file> fails and returns false.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &test_file
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : name of the file that ultimately passes the test
#@DESCRIPTION: Perform file test(s) on a filename and, if needed, 
#              variations on that filename implied by a list of extensions.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Greg Ward, March 1996
#@MODIFIED   : 1997/03/06, added "pgp" extension
#              1997/05/01, changed so we always test $_ implicitly -- that
#                          way caller can supply a fancier test expression
#              1997/05/02, changed to use $_ for filename so caller can
#                          supplier fancier set of file test(s)
#-----------------------------------------------------------------------------
sub test_file
{
   my ($test, $file, $variants) = @_;
   my ($variant_re);
   local $_;

   # default list of variant extensions

   if (defined $variants)
   {
      if ($variants && ref $variants ne 'ARRAY')
      {
         croak "test_file: \$variants must be an array ref, a false " .
               "scalar value, or not supplied";
      }
   }
   else                                 # not supplied -- use default list
   {
      $variants = [qw (gz z Z)];
   }

   # At this point, if $variants is true it must be an array ref.

   $variant_re = join ("|", @$variants) if $variants;


   # If $file as supplied passes the test, immediately return success
   
   $_ = $file;
   return $_ if (eval $test);
   croak "test_file: error in \$test argument: $@" if $@;


   # OK, that didn't work -- get clever by trying out variant filenames,
   # but only if the user-supplied list of variants is not empty (see
   # check_files for an example of an empty list of variants -- it is
   # occasionally convenient!)

   if ($variants)
   {
      # First, try stripping off the variant extensions.  If that works, it
      # means the passed-in filename already had an extension (eg. it's
      # already compressed), so let's try testing the base filename.

      if (s/\.($variant_re)$//)
      {
         return $_ if (eval $test);
      }

      # Now, at this point we could be in one of two situations: either the
      # original filename is intact (the s/// didn't remove any
      # extensions), or we have stripped off an extension and the test
      # failed on the base filename.

      # In the former case ('.mnc.gz' didn't work, tried '.mnc' and it 
      # also didn't work), we'll give up now.  We could conceivably
      # try the other variant extensions on the base filename, but
      # that's just getting a little overenthusiastic.  However, if we 
      # didn't manage to strip off any existing variant extensions, we
      # should definitely test the file with all the different extensions.

      else
      {
         my $ending;
         for $ending (@$variants)
         {
            $_ = "$file.$ending";
            return $_ if (eval $test);
         }
      }
   }
   
   # If we make it to here, then all tests failed -- hey, we did our best!

   return '';
}


=back

=head2 Search routines

=over 4

=item search_directories (FILE, DIRS [, TEST])

Searches for FILE in the directories listed in DIRS, which must be an
array ref.  The current directory may be denoted in DIRS either as a
single dot or as the empty string.

The optional argument TEST can be used to supply a file-test operator used
to determine if FILE in fact "exists" in a given directory; e.g., if you
require that a file exist and not be a symbolic link, TEST could be the
string C<"-e && ! -l">.  This works because TEST is C<eval>'d with C<$_>
set to the filename currently under consideration, and the file-test
operators (except C<-t>) default to working on C<$_>.

Returns false if FILE wasn't found in any of the directories in DIRS,
otherwise returns the directory where FILE was found.  The directory is
returned in a form suitable for direct concatenation with FILE,
i.e. either the empty string (if it was supplied in DIRS) or with a
trailing slash.

=cut


# ------------------------------ MNI Header ----------------------------------
#@NAME       : search_directories
#@INPUT      : $file - name of file to search for
#              @dirs - list of directories to search in.  Note that
#                 the empty string may be used to denote the current 
#                 directory.
#              $test - file-test operator expression used to determine
#                 if a file "exists" in a given directory
#@OUTPUT     : 
#@RETURNS    : The directory where $file was found, or undef if it wasn't.
#              The directory is returned in a form suitable for directly
#              concatenating with the filename, i.e. either as an empty
#              string (current directory) or with a trailing slash.
#@DESCRIPTION: Searches a list of directories for a single file.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1994/09/16, Greg Ward
#@MODIFIED   : 1997/04/28, GW: changed to take an array ref for list of dirs,
#                          and allowed caller-supplied test code
#-----------------------------------------------------------------------------
sub search_directories
{
   my ($file, $dirs, $test) = @_;
   my ($dir, $found);

   croak ("dirs argument must be an array ref") unless ref $dirs eq 'ARRAY';
   $test = '-e' unless defined $test;

   my @dirs = @$dirs;                   # so we don't clobber caller's data
   normalize_dirs (@dirs);
   $found = 0;
   local $_;
   foreach $dir (@dirs)
   {
      $_ = $dir . $file;
      $found = eval $test;
      croak ("bad test: $test ($@)") if $@;
      return $dir if $found;
   }

   return undef;
}


=item find_program (PROGRAM [, PATH])

C<find_program> is a front-end to C<search_directories> for finding
executable programs.  It has the following differences from
C<search_directories>:

=over 4

=item *

can accept the search path either as a reference to a list of
directories (same as C<search_directories>) or as a colon-separated
string

=item *

search path defaults to C<$ENV{'PATH'}> (so you don't actually need that
search-path-as-string feature very often)

=item *

prints a warning if PROGRAM was not found (as opposed to
C<search_directories>, which just returns false and lets you take care
of informing the user)

=item *

you can't specify the file test---it's hard-coded to C<"-f && -x">.

=item *

C<find_program> returns the complete path of the found program
(directory plus program name), rather than just the directory where the
program was found

=back

Apart from that, though, the two subroutines act the same.  In
particular, C<find_program> also returns false if PROGRAM wasn't found
in any of the directories in PATH.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &find_program
#@INPUT      : $program - name of program to search for
#              $path    - colon-delimited list of directories to look in
#                         (if not supplied, $ENV{"PATH"} will be used);
#                         OR a reference to a list of directories
#@OUTPUT     : 
#@RETURNS    : full path of program, or 0 if not found (also prints a 
#              warning if not found)
#@DESCRIPTION: Searches a list of directories for an executable program.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/07/20, Greg Ward
#@MODIFIED   : 1997/05/05, GW: changed into a simple front-end for 
#                          search_directories
#-----------------------------------------------------------------------------
sub find_program
{
   my ($program, $path) = @_;
   my (@path, $found, $dir, $fullpath);

   $path = $ENV{'PATH'} unless defined $path;

   if (! ref $path)              { @path = split (":", $path) }
   elsif (ref $path eq 'ARRAY')  { @path = @$path }
   else 
   {
      croak "\$path argument must be either an array ref or a scalar\n";
   }

   $dir = search_directories ($program, \@path, '-f && -x');
   return "$dir$program" if $dir;
   warn "Couldn't find program \"$program\"\n";
   return 0;
}


=item find_programs (PROGRAMS [, PATH])

C<find_programs> calls C<find_program> for each program listed in
PROGRAMS.  PROGRAMS must be a reference to a list of program names; PATH
is the same as for C<find_program>, i.e. it can be a reference to a list
of directories, a colon-separated string, or if not given it defaults to
C<$ENV{'PATH'}>.

If all programs listed in PROGRAMS are found, returns a list of complete
paths to those programs.  If any are not found, C<find_program> will
print a warning and C<find_programs> will return an empty list.  Thus, a
common idiom is:

   @programs = qw(ls rm mv cp);
   @programs = find_programs (\@programs);
   exit 1 unless @programs;

(Note that if you are using the F<MNI::Spawn> module, you'll probably never
need to call C<find_programs> directly.  Rather, there is a
C<RegisterPrograms> subroutine in F<MNI::Spawn> that maintains a private
hash of all "known" programs and their full paths, so you never have to
worry about keeping track of both program names and their full paths.
Unsurprisingly, C<MNI::FileUtilities::find_programs> is called by
C<MNI::Spawn::RegisterPrograms>.  See the L<MNI::Spawn> for
more details.)

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &find_programs
#@INPUT      : @$programs  - list of programs to search for
#              $path       - reference to list of directories to search
#                            (OR a colon-delimited string)
#@OUTPUT     : 
#@RETURNS    : list of found programs (as full pathnames)
#              OR empty list (if there were any missing programs)
#@DESCRIPTION: Searches for each program specified in the specified search
#              path.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &find_program
#@CREATED    : 1995/12/08, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub find_programs
{
   my ($programs, $path) = @_;
   my ($missing, $prog, $found, @found);

   # We search for *all* requested programs, even if one isn't found --
   # that way, the user will see error messages for all missing programs,
   # not just the one that happens to turn up missing first.

   $missing = 0;
   foreach $prog (@$programs)
   {
      $found = &find_program ($prog, $path);
      $missing++ if ! $found;
      push (@found, $found);
   }
   return @found if $missing == 0;
   return ();
}

=back

=head2 Miscellaneous routines

=over 4

=item generate_numbered_filename (BASE, EXT [, ADD_DATE])

Generates a new filename in a numbered sequence, with the current date
optionally added.  Works by generating a filename like C<BASE_${i}EXT>,
and incrementing C<$i> until the named file does not exist.  If C<$i> is
1, omits the number from the filename; it will be renamed the next time 
you call C<generate_numbered_filename> with the same BASE and EXT.

For example, the very first call like this (i.e. before any C<foo*.log>
files exist):

   $file = generate_numbered_filename ('foo', '.log');

would return C<"foo.log">.  Assuming you then use that filename to
create a file, the next call would notice that C<"foo.log"> exists, but
C<"foo_2.log"> does not exist.  It would thus rename C<"foo.log"> to
C<"foo_1.log">, and return C<"foo_2.log">.  Future calls would return
C<"foo_3.log">, C<"foo_4.log">, etc.

If ADD_DATE is true, the current date (formatted as YYYY-MM-DD) is
appended to BASE before anything else is done.

Dies on any error, of which there are currently only two.  The first
possible error is that C<"foo.log"> and C<"foo_1.log"> both exist; this
should never happen if you only use C<generate_numbered_filename> to
generate filenames for this sequence, so it's considered sufficiently
serious to C<die> on.  The other possibile error is that C<rename>
failed, which would also cause a corrupt sequence of filenames---hence
it's deemed fatal as well.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &generate_numbered_filename
#@INPUT      : $base - first part of filename
#              $ext  - last part of filename (including "." if wanted)
#              $add_date - flag: if true, will add "_yyyy_mm_dd" after base
#@OUTPUT     : 
#@RETURNS    : Empty string on error (conflicting filenames or error 
#              renaming); otherwise, next filename in numbered sequence
#              starting with $base.
#@DESCRIPTION: Generates a numbered filename by incrementing a counter
#              $i until ${base}_${i}${ext} is found not to exist.  If
#              $i is 1 -- i.e. there weren't any files named with $base
#              and $ext -- then "_$i" is left out of the filename entirely.
#
#              For example, if called with $base="foo" and $ext=".log", and
#              neither "foo.log" nor "foo_1.log" exist, returns "foo.log".
#              On the next call, "foo.log" will be renamed to "foo_1.log",
#              and "foo_2.log" is returned.  Subsequent calls return
#              "foo_3.log", "foo_4.log", etc.  If both "foo.log" and
#              "foo_1.log" exist, then we print a warning and return the
#              empty string -- you'll have to deal with this degenerate
#              situation yourself, because it should never arise if you
#              only use &generate_numbered_filename to generate filenames.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1996/08/01, GPW, from code in ICBM.pm
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub generate_numbered_filename
{
   my ($base, $ext, $add_date) = @_;
   my $i = 1;

   $base .= strftime ("_%Y-%m-%d", localtime (time))
      if $add_date;

   if (-e "${base}${ext}")
   {
      if (-e "${base}_1${ext}")
      {
	 die "conflicting filenames: ${base}${ext} and ${base}_1${ext}\n";
      }
      else
      {
	 rename ("${base}${ext}", "${base}_1${ext}") ||
            die ("unable to rename ${base}${ext}: $!\n");
      }
   }

   $i++ while (-e "${base}_${i}${ext}");
   ($i == 1) ? "${base}${ext}" : "${base}_${i}${ext}";
}


=item statfs (PATH)

Does a system call to C<statfs(2)>.  This is very non-portable, and
currently only works on IRIX and Linux/i86.  Dies if called on
any other architecture.  Return values are:

   ($type, $bsize, $blocks, $bfree, $files, $ffree) = statfs ($path);

Note that this is merely a stopgap measure until the mythical
F<File::statfs> (or maybe F<Filesystem::stat>) module appears on CPAN.
When and if that happens, I reserve the right to remove C<statfs> from
F<MNI::FileUtilities>.

=cut


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &statfs
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : list of useful-sounding values that are common to IRIX 
#              and Linux:
#                 $type    - filesystem (see your header files for definitions)
#                 $bsize   - block size (in bytes)
#                 $blocks  - total number of blocks in filesystem
#                 $bfree   - free blocks in filesystem (under Linux, this
#                            will be the "available block" count -- ie.
#                            number of blocks available to non-superuser)
#                 $files   - number of file nodes
#                 $ffree   - number of available file nodes
#@DESCRIPTION: Attempts to call the statfs(2) system call.  Will only 
#              work on Linux/i86 or IRIX.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1997/03/06, GPW
#@MODIFIED   : 
#@COMMENTS   : there is a File::statfs (or maybe Filesystem::stat?) module
#              mentioned in the module list, but no sign of it on CPAN.  Hmmm.
#-----------------------------------------------------------------------------
sub statfs
{
   require 5.003;                       # for $^O

   my ($path) = @_;
   my ($buf, $r);
   my ($type, $pad, $bsize, $frsize, $blocks, $bfree, $bavail);
   my ($files, $ffree, $fsid, $namelen, $spare, $fname, $fpack);

   if ($^O eq 'linux')
   {
      # structure size taken from i86 Linux 2.0 man pages; only tested
      # on Linux 2.0/i86 

      require "syscall.ph";
      $buf = ' ' x ( (7 + 2 + 1 + 6) * 4);
      $r = syscall (&SYS_statfs, $path, $buf);
      ($type,$bsize,$blocks,$bfree,$bavail,$files,$ffree,$fsid,$namelen,$spare)
         = unpack ("lllllll2ll6", $buf);
      $bfree = $bavail;         # ignore the free/available distinction (RTFM)
   }
   elsif ($^O eq 'irix')
   {
      my $len = (2 +2 + (6 * 4) + 6 + 6);
      $buf = ' ' x $len;
      $r = syscall (1035, $path, $buf, $len, 0);
      ($type,$pad,$bsize,$frsize,$blocks,$bfree,$files,$ffree,$fname,$fpack)
         = unpack ("ssllllllc6c6", $buf);
   }
   else
   {
      die "Sorry, I don't know how to do `statfs' under $^O\n";
   }

   if ($r == 0)                         # success?
   {
      return ($type, $bsize, $blocks, $bfree, $files, $ffree);
   }
   else                                 # failure
   {
      warn "statfs failed on \"$path\": $!\n";
      return;
   }
}

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
