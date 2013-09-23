# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::MiscUtilities
#@DESCRIPTION: Miscellaneous and unclassifiable (but otherwise useful!)
#              utility routines
#@EXPORT     : timestamp 
#              userstamp 
#              lcompare
#              nlist_equal
#              make_banner
#              shellquote
#@EXPORT_OK  : 
#@EXPORT_TAGS:
#@USES       : POSIX, Sys::Hostname, Cwd
#@REQUIRES   : Exporter
#@CREATED    : 1997/04/24, Greg Ward (from misc_utilities.pl)
#@MODIFIED   : 
#@VERSION    : $Id: MiscUtilities.pm,v 1.7 1997/10/03 13:37:04 greg Rel $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::MiscUtilities;

use strict;
use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

require 5.002;
require Exporter;
require AutoLoader;

use POSIX qw(strftime);
use Sys::Hostname;
use Cwd;

@ISA = qw(Exporter);
@EXPORT_OK = qw(timestamp
                userstamp
                lcompare
                nlist_equal
                make_banner
                shellquote);
%EXPORT_TAGS = (all => \@EXPORT_OK);

*AUTOLOAD = \&AutoLoader::AUTOLOAD;

__END__

=head1 NAME

MNI::MiscUtilities - miscellaneous and unclassifiable utility routines

=head1 SYNOPSIS

   use MNI::MiscUtilities qw(:all);

   $when = timestamp ([TIME])

   $whowhere = userstamp ([USER [, HOST [, DIR]]])

   $cmp = lcompare (COMPARE_FN, LIST1, LIST2)

   $cmp = nlist_equal (LIST1, LIST2)

   $banner = make_banner (MSG [, CHAR [, WIDTH]])

   $cmd_string = shellquote (WORDLIST)

=head1 DESCRIPTION

F<MNI::MiscUtilities> provides a handful of otherwise unclassifiable
utility routines.  Don't go looking for a common thread of purpose or
operation---there isn't one!

=over 4

=item timestamp ([TIME])

Formats TIME in a complete, unambiguous, ready-to-sort fashion:
C<yyyy-mm-dd hh:mm:ss>.  TIME defaults to the current time; if it is
supplied, it should be a time in the standard C/Unix representation:
seconds since 1970-01-01 00:00:00 UTC, as returned by Perl's built-in
C<time> function.

Returns a string containing the formatted time.

=cut

#
# IDEA: should timestamp and userstamp be moved to a new module, say
# MNI::Footprint (should only be needed by Spawn, Backgroundify, and 
# MINC history stuff)?
#

# ------------------------------ MNI Header ----------------------------------
#@NAME       : timestamp
#@INPUT      : $tm - [optional] time to use, as seconds since 
#                    1970-01-01 00:00:00 UTC (eg from `time'); 
#                    defaults to the current time
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Generates and returns a timestamp of the form 
#              "1995-05-16 22:30:14".
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/16, GW (from &doit)
#@MODIFIED   : 1996/05/22, GW: added seconds to time
#              1996/06/17, GW: changed to use strftime from POSIX
#              1997/04/24, GW: copied from misc_utilities.pl, removed brackets
#-----------------------------------------------------------------------------
sub timestamp #(;$)
{
   my ($tm) = @_;

   $tm = time unless defined $tm;
   strftime ('%Y-%m-%d %H:%M:%S', localtime ($tm));
}


=item userstamp ([USER [, HOST [, DIR]]])

Forms a useful complement to C<timestamp>; where C<timestamp> tells the
"when" of an action, C<userstamp> gives the "who" and "where".  That is,
C<userstamp> generates and returns a string containing the current
username, host, and working directory, e.g. C<user@host:/directory>.

Normally, no parameters are given to C<userstamp>---it uses C<$E<lt>> (the
real uid) and C<getpwuid> to get the username, C<Sys::Hostname::hostname>
to get the hostname, and C<Cwd::getcwd> to get the current directory.  If
you wish to generate a bogus "userstamp", though, you may do so by
overriding some or all of C<userstamp>'s arguments.  For instance, to
supply a fake directory, but use the defaults for USER and HOST:

   userstamp (undef, undef, '/fake/dir');

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : userstamp
#@INPUT      : $user - [optional] username; defaults to looking up 
#                      login name of $< (real uid) in password file
#              $host - [optional]; defaults to hostname from Sys::Hostname
#              $dir  - [optional]; defaults to current directory, from 
#                      Cwd::getcwd
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Generates and returns a "userstamp" of the form 
#              "greg@bottom:/data/scratch1/greg".
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/05/16, GW
#@MODIFIED   : 1996/05/29, GW: added directory
#              1997/04/24, GW: copied from misc_utilities.pl, removed brackets
#-----------------------------------------------------------------------------
sub userstamp #(;$$$)
{
   my ($user, $host, $dir) = @_;

   $user = getpwuid ($<) unless defined $user;
   $host = hostname() unless defined $host;
   $dir = getcwd unless defined $dir;
   sprintf ("%s@%s:%s", $user, $host, $dir);
}


=item lcompare (COMPARE_FN, LIST1, LIST2)

Compares two lists, element-by-element, and returns -1, 0, or 1, depending
on whether LIST1 is less than, equal to, or greater than LIST2.  COMPARE_FN
must be a reference to a subroutine that compares individual elements and
returns -1, 0, or 1 appropriately.  The elements to compare are passed in
as C<@_>, so the body of this subroutine will usually look like C<$_[0] cmp
$_[1]> or C<$_[0] E<gt>=E<lt> $_[1]>, depending on whether you're dealing
with lists of strings or of numbers.  LIST1 and LIST2 must both be list
references.

The semantics of list comparison are identical to those for string
comparison.  In particular, two lists are equal if and only if they have
the same length, and all corresponding pairs of elements are identical.  If
two lists are of the same length but have different elements at position
I<i>, then the list with the greater element at position I<i> is greater,
regarldess of what comes after position I<i>.  If LIST1 and LIST2 are
identical up to the last element of LIST2, and LIST1 is longer, then LIST1
is greater.  If they are identical up to the last element of LIST1, and
LIST2 is longer, then LIST2 is greater.

For example, the lists in the left-hand column are greater than the
lists in the right-hand column:

      (3,4,5)                (3,4,4)
      (3,4,4)                (3,4)
      (3,4,5)                (3,4)

Incidentally, the semantic equivalence of list and string comparison
means that, for strings C<$s1> and C<$s2>, the following is always true:

   lcompare (sub { $_[0] cmp $_[1] }, [split ('', $s1)], [split ('', $s2)])
     == $s1 cmp $s2

=cut

# Had an interesting time trying to make my `lcompare' act like
# builtin `sort', eg. so you could do any of these:
#
#    lcompare { $_[0] <=> $_[1] } @a, @b
#    $ncomp = sub { $_[0] <=> $_[1] }
#    lcompare (sub { $_[0] <=> $_[1] }, @a, @b)
#    lcompare ($ncomp, @a, @b)
#
# but it turns out that prototypes just plain aren't that flexible
# -- at least, I couldn't figure out.  Perhaps there's a reason
# that table of prototypes you could use to replace builtins doesn't
# include mysort!
#
# So I'm doing it the obvious, non-prototyped way -- caller must
# pass in explicit references (one code ref, to array refs).


# Here's some things I found out while playing around with the
# prototype version of lcompare:
#
# CODE                                     compiles ok?  result ok?
# compare (sub { $_[0] == $_[1] }, @a, @b)      yes         yes
# compare { $_[0] == $_[1] }, @a, @b            yes          no
# compare { $_[0] == $_[1] } @a, @b             yes         yes
# compare ({ $_[0] == $_[1] } @a, @b)            no
# compare ({ $_[0] == $_[1] }, @a, @b)           no

# ------------------------------ MNI Header ----------------------------------
#@NAME       : lcompare
#@INPUT      : $cmp   - [code ref] comparison function, takes 2 args
#                       and returns -1, 0, or 1, depending on whether first
#                       is less than, equal to, or greater than second
#              $alist - [array ref] first array
#              $blist - [array ref] second array
#@OUTPUT     : 
#@RETURNS    : 0 if the two arrays are equal
#              -1 if @$alist is smaller than @$blist
#              1 if @$alist is greater than @$blist
#@DESCRIPTION: Compares two arrays, element by element, and returns
#              an integer telling which is `larger'.
#@CREATED    : 1997/04/24, Greg Ward
#-----------------------------------------------------------------------------
sub lcompare # (&\@\@)
{
   my ($cmp, $alist, $blist) = @_;
   my ($i, $result);

   # goal: lcompare { $a cmp $b } [split ("", $s1)], [split ("", $s2)]
   # should be same as $s1 cmp $s2

   $result = 0;
   for $i (0 .. $#$alist)
   {
      my ($a, $b) = ($alist->[$i], $blist->[$i]);
      return 1 if !defined $b;          # list a is longer
      $result = &$cmp ($a, $b);
      return $result if $result != 0;
   }

   return -1 if $#$blist > $#$alist;	# equal up to end of a, but b longer
   return 0;                            # they're equal
}


=item nlist_equal (LIST1, LIST2)

Uses C<lcompare> to compare two lists of numbers, and returns true if they
are equal.  LIST1 and LIST2 must be list references.  Note that the boolean
sense of C<nlist_equal> is reversed from that of C<lcompare>,
i.e. C<nlist_equal> returns true if C<lcompare> returns 0.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : nlist_equal
#@INPUT      : $alist, $blist - [array refs] the two lists to compare
#@OUTPUT     : 
#@RETURNS    : true if the two lists are numerically identical, false otherwise
#@DESCRIPTION: Compares two lists numerically.  
#@CALLS      : lcompare
#@CREATED    : 1997/04/25, GPW
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub nlist_equal
{
   my ($alist, $blist) = @_;

   (lcompare (sub { $_[0] <=> $_[1] }, $alist, $blist)) == 0;
}


=item make_banner (MSG [, CHAR [, WIDTH]])

Creates and returns a string of the form C<-- Hello! ---------->
(assuming MSG is C<'hello!'>, CHAR is C<'-'>, and WIDTH is 20.  CHAR
defaults to C<'-'>, and WIDTH defaults to 80 (although I may eventually
change this to the width of the terminal).

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : make_banner
#@INPUT      : $msg    - the string to print
#              $char   - the character to use when making the "banner"
#                        (optional; defaults to "-")
#              $width  - the width of field to pad to (optional; defaults
#                        to 80, but should default to width of terminal)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Creates and returns a string of the form 
#              "-- Hello! ----------" (assuming $msg="Hello!", $char="-", 
#              and $width=20)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1996/05/22, Greg Ward - adapted from do_mritopet
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub make_banner
{
   my ($msg, $char, $width) = @_;

   $width = 80 unless $width;           # should this use Term::Cap?!?
   $char = "-" unless $char;

   my $banner = $char x 2 . " " . $msg . " ";
   $banner .= $char x ($width - length ($banner)) . "\n"
}


=item shellquote (WORDLIST)

Performs the opposite of the F<Text::ParseWords> module, namely it joins
an array of words together, with some sub-strings quoted in order to
escape shell meta-characters.  WORDLIST should just be a list of
substrings, not a list reference.  This is useful for turning a list of
arguments (such as C<@ARGV>, or something you're about to pass to Perl's
C<system>) into a string that looks like what you might type to the
shell.

The exact rules are as follows: if a word contains no metacharacters and
is not empty, it is untouched.  If it contains both single and double
quotes (C<'> and C<">), all meta-characters are escaped with a
backslash, and no quotes are added.  If it contains just single quotes,
it is encased in double quotes.  Otherwise---that is, if it is empty or
contains meta-characters other than C<'>---it is encased in single
quotes.

The list of shell meta-characters is taken from the Perl source code
(C<do_exec()>, in doio.c), and thus is specific to the Bourne shell:

   $ & * ( ) { } [ ] ' " ; \ | ? < > ~ ` \n

(plus whitespace).

For example, if C<@ARGV> is C<("foo", "*.bla")>, then
C<shellquote (@ARGV)> will return C<"foo '*.bla'">---thus turning a
simple list of arguments into a string that could be given to the shell
to re-generate that list of arguments.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : &shellquote
#@INPUT      : @words - list of words to possibly quote or escape
#@OUTPUT     : 
#@RETURNS    : concatenation of @words with necessary quotes and backslashes
#@DESCRIPTION: The inverse of shellwords -- takes a list of arguments 
#              (like @ARGV, or a list passed to system or exec) and 
#              escapes meta-characters or encases in quotes as appropriate
#              to allow later processing by the shell.  (/bin/sh, in 
#              particular -- the list of metacharacters was taken from
#              the Perl source that does an exec().)
#@METHOD     : If a word contains no metacharacters and is not empty, it is
#              untouched.  If it contains both single and double quotes,
#              all meta- characters are escaped with a backslash, and no
#              quotes are added.  If it contains just single quotes, it is
#              encased in double quotes.  Otherwise, it is encased in
#              single quotes.
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1996/11/13, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub shellquote
{
   my (@words) = @_;
   
   local $_;
   for (@words)
   {
      # This list of shell metacharacters was taken from the Perl source
      # (do_exec(), in doio.c).  It is, in slightly more readable form:
      # 
      #    $ & * ( ) { } [ ] ' " ; \ | ? < > ~ ` \n
      #
      # (plus whitespace).  This totally screws up cperl-mode's idea of
      # the syntax, unfortunately, so don't expect indenting to work
      # at all in the rest of this function.

      if ($_ eq "" || /[\s\$\&\*\(\)\{\}\[\]\'\";\\\|\?<>~`\n]/)
      {
         # If the word has both " and ' in it, then just backslash all 
         #   metacharacters;
         # if it has just ' then encase it in "";
         # otherwise encase it in ''

         SUBST:
         {
            (s/([\s\$\&\*\(\)\{\}\[\]\'\";\\\|\?<>~`\n])/\\$1/g, last SUBST)
               if (/\"/) && (/\'/);
            ($_ = qq/"$_"/, last SUBST) if (/\'/);
            $_ = qq/'$_'/;
         }
      }
   }

   join (" ", @words);
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
