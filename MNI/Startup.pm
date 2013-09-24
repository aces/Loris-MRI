# ------------------------------ MNI Header ----------------------------------
#@NAME       : MNI::Startup
#@DESCRIPTION: Perform common startup/shutdown tasks.
#@EXPORT     : (read the docs for how exports work with this module)
#@EXPORT_OK  : 
#@EXPORT_TAGS: 
#@USES       : Carp, Cwd, MNI::MiscUtilities
#@REQUIRES   : Exporter
#@CREATED    : 1997/07/25, Greg Ward (from old Startup.pm, rev. 1.23)
#@MODIFIED   : 
#@VERSION    : $Id: Startup.pm,v 1.11 2000/02/21 22:57:54 stever Exp $
#@COPYRIGHT  : Copyright (c) 1997 by Gregory P. Ward, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#
#              This file is part of the MNI Perl Library.  It is free 
#              software, and may be distributed under the same terms
#              as Perl itself.
#-----------------------------------------------------------------------------

package MNI::Startup;

use strict;
use vars qw(@EXPORT_OK %EXPORT_TAGS);
use vars qw($ProgramDir $ProgramName $StartDirName $StartDir);
use vars qw($Verbose $Execute $Clobber $Debug $TmpDir $KeepTmp @DefaultArgs);
use Carp;

require 5.002;
require Exporter;

%EXPORT_TAGS = 
   (progname => [qw($ProgramDir $ProgramName)],
    startdir => [qw($StartDirName $StartDir)],
    optvars  => [qw($Verbose $Execute $Clobber $Debug $TmpDir $KeepTmp)],
    opttable => [qw(@DefaultArgs)],
    cputimes => [],
    cleanup  => [],
    sig      => [],
    subs     => [qw(self_announce backgroundify)]);

map { push (@EXPORT_OK, @{$EXPORT_TAGS{$_}}) } keys %EXPORT_TAGS;


=head1 NAME

MNI::Startup - perform common startup/shutdown tasks

=head1 SYNOPSIS

   use MNI::Startup;

   use MNI::Startup qw([optvars|nooptvars] 
                       [opttable|noopttable]
                       [progname|noprogname]
                       [startdir|nostartdir]
                       [cputimes|nocputimes]
                       [cleanup|nocleanup]
                       [sig|nosig]);

   self_announce ([$log [, $program [, $args]]]);

   backgroundify ($log [, $program [, $args]]);

=head1 DESCRIPTION

F<MNI::Startup> performs several common tasks that need to be done at
startup and shutdown time for most long-running,
computationally-intensive Perl scripts.  (By "computationally-intensive"
here I mean not that the script itself does lots of number
crunching---rather, it runs other programs to do its work, and acts to
unify a whole sequence of lower-level computational steps.  In other
words, F<MNI::Startup> is for writing glorified shell scripts.)

Each startup/shutdown task is independently controllable by a short
"option string".  The tasks, and the options that control them, are:

=over 4

=item C<progname>

Split C<$0> up into program name and directory.

=item C<startdir>

Get the starting directory and split off the last component (the
"start directory name").

=item C<optvars>

Initialize several useful global variables: C<$Verbose>,
C<$Execute>, C<$Clobber>, C<$Debug>, C<$TmpDir>, and C<$KeepTmp>.

=item C<opttable>

Create an option sub-table that can be incorporated into a larger option
table for use with the F<Getopt::Tabular> module.

=item C<cputimes>

Keep track of elapsed CPU time and print it out at exit time (depending on
certain other conditions).

=item C<cleanup>

Clean up a temporary directory at exit time (depending on certain other
conditions).

=item C<sig>

Install a signal handler to cleanup and die whenever we are hit by
certain signals.

=back 

By default, F<MNI::Startup> does everything on this list (i.e., all
options are true).  Options are supplied to the module via its import
list, and can be negated by prepending C<'no'> to them.  For instance,
if you want to disable printing CPU times and signal handling, you
could supply the C<nocputimes> and C<nosig> tokens as follows:

   use MNI::Startup qw(nocputimes nosig);

Note that having a particular option enabled usually implies two things:
a list of variable names that are exported into your namespace at
compile-time, and a little bit of work that F<MNI::Startup> must do at
run-time.  Thus, you don't have the kind of fine control over selecting
what names are exported that you do with most modules.  The exact
details of what work is done and which names are exported are covered in
the sections below.

=cut

# Necessary overhead.  The %options hash dictates what we will do and
# which lists of names will be exported; %option_exports contains
# the actual export sub-lists.

my %options = 
   (progname => 1,
    startdir => 1,
    optvars  => 1,
    opttable => 1,
    cputimes => 1,
    cleanup  => 1,
    sig      => 1,
    subs     => 1);

# @start_times is set when we run the module, and compared to the 
# ending times in &cleanup

my @start_times;

# %signals is used to generate the error message that we print on being
# hit by one of these signals; it also determines what signals we can
# catch.  The list is culled by checking that each signal already has a
# value in %SIG -- this tells us that a signal is "known" to Perl,
# i.e. won't trigger a warning when we try to install a handler for it.
# (We could perhaps cull further by requiring that that value be defined
# -- then we wouldn't override existing or built-in signal handlers such
# as for SEGV.  I think it's probably OK to override them, though.)

my %signals =
   (HUP  => 'hung-up', 
    INT  => 'interrupted', 
    QUIT => 'quit',
    ILL  => 'illegal instruction',
    TRAP => 'trace trap',
    ABRT => 'aborted',
    IOT  => 'I/O trap',
    EMT  => 'EMT instruction',
    FPE  => 'floating-point exception',
    BUS  => 'bus error',
    SEGV => 'segmentation violation',
    SYS  => 'bad argument to system call',
    PIPE => 'broken pipe',
    TERM => 'terminated',
    USR1 => 'user-defined signal 1',
    USR2 => 'user-defined signal 2');

# $orig_tmpdir is the temporary directory name actually cooked up in
# &startup; the user can only touch $TmpDir, the global version of this.
# That way, we won't nuke a custom temp dir on exit, only the one
# that we cook up.

my $orig_tmpdir;


# Here we process the import list.  We walk over the entire list once,
# checking it for validity, setting the appropriate option flags; then
# we walk the list of all options to build the export list, and call
# Exporter's import method to do all the hard work for us.

sub startup;

sub import
{
   my ($classname, @imports) = @_;
   my @exports;

   my ($item, $negated);
   foreach $item (@imports)
   {
      $negated = ($item =~ s/^no//);
      croak "MNI::Startup: unknown option \"$item\""
         unless exists $options{$item};

      $options{$item} = ! $negated;
   }

   my $option;
   foreach $option (keys %options)
   {
      push (@exports, ":$option")
         if ($options{$option});
   }

   local $Exporter::ExportLevel = 1;    # so we export to *our* user, not
                                        # Exporter's!
   Exporter::import ('MNI::Startup', @exports);
   startup;

}  # import


=head1 PROGRAM NAME AND START DIRECTORY

The first two tasks done at run-time are trivial, but important for
intelligent logging, useful error messages, and safe cleanup later on.
First, F<MNI::Spawn> splits C<$0> up into the "program directory" (up to
and including the last slash) and the "program name" (everything after
the last slash).  These two components are put into C<$ProgramDir> and
C<$ProgramName>, both of which will be exported to your program's
namespace if the C<progname> option is true (which, like with all of
F<MNI::Startup>'s options, is the default).  If there are no slashes in
C<$0>, then C<$ProgramDir> will be empty.

Next, if necessary, F<MNI::Startup> gets the current directory (using
C<Cwd::getcwd>) and saves it in C<$StartDir>; the last component of this
directory is also extracted and saved in C<$StartDirName> (hey, you
never know when you might want it).  This can be turned off by setting
the C<startdir> option to false; under certain obscure circumstances,
though, F<MNI::Startup> will decide that it really does need to know the
startup directory and will call C<Cwd::getcwd> anyways.  In any case,
the two variables are only exported to your namespace if C<startdir> is
true.

=cut

=head1 OPTION VARIABLES AND OPTION TABLE

Most long-running, computationally intensive scripts that spend a lot of
time running other programs and read/write lots of (potentially big)
files should be flexible enough for users to control a couple of basic
aspects of their behaviour: the level of verbosity, whether sub-programs
will actually be executed, whether pre-existing files should be
clobbered, where to write temporary files, whether to clean up those
temporary files, and so on.  As it happens, F<MNI::Spawn> provides a
tailored solution to these problems, including global variables to guide
the flow of control of your program and an option sub-table (for use
with F<Getopt::Tabular>) to allow the end user of your program to set
those globals.  These variables are only initialized and exported if the
C<optvars> option is true, and the option table is only initialized and
exported if the C<opttable> option is true.

=head2 Option variables

Most of the option variables initialized and exported by F<MNI::Spawn>
are boolean flags.  Thus, each one has both a positive and negative
option in the table meant for use with F<Getopt::Tabular>.  As explained
in the F<Getopt::Tabular> documentation, use of the positive option
means the associated variable will be set to 1, and the negative option
will set it to 0.  The variables, and the command-line options (in
positive/negative form for the boolean options) that can be used to
control them, are:

=over 4

=item C<$Verbose> (C<-verbose>/C<-quiet>) (initialized to: 1)

To be used as you see fit, but keep in mind that it is surreptitiously
used by other modules (F<MNI::Spawn> in particular---see the C<verbose>
option in its documentation).  I use it to control printing out useful
information to the user, echoing all executed command lines, and
controlling the verbosity of sub-programs (these last two with the help
of the F<MNI::Spawn> module).

=item C<$Execute> (C<-execute>/C<-noexecute>) (initialized to: 1)

Again to be used as you see fit, but also used by other modules (see
C<execute> in F<MNI::Spawn>).  I use it to control both the execution of
sub-programs (with F<MNI::Spawn>) and any operations that might affect
the filesystem---e.g. I only create directories or files if C<$Execute>
is true.

=item C<$Clobber> (C<-clobber>/C<-noclobber>) (initialized to: 0)

Use it to decide whether or not to overwrite existing files.  Generally,
my approach is that if C<$Clobber> is true, I will silently overwrite
existing files (which is what Unix tends to do for you anyways); if it
is false, a pre-existing file is either a fatal error or is used instead
of being re-created (depending on the context).  C<$Clobber> should also
be propagated to the command lines of sub-programs that support such an
option using F<MNI::Spawn>'s default arguments feature.

=item C<$Debug> (C<-debug>/C<-nodebug>) (initialized to: 0)

Controls whether you should print debugging information.  The quantity
and nature of this information is entirely up to you; C<$Debug> should
also be propagated to sub-programs that support it.

=item C<$TmpDir> (C<-tmpdir>)

Specifies where to write temporary files; this is initialized to a
unique directory constructed from C<$ProgramName> and the process id
(C<$$>).  This (hopefully) unique name is appended to
C<$ENV{'TMPDIR'}> to make the complete directory.  If the TMPDIR
environment variable doesn't exist, then the following directories
are checked, and the first found is used: C<'/usr/tmp'>, C<'/var/tmp'>,
and C<'/tmp'>.  If C<$ENV{'TMPDIR'}> specifies a relative
path, C<$TmpDir> is made into an absolute path by prepending the current
directory (from C<$StartDir>---this is the "certain obscure
circumstance" where F<MNI::Startup> ignores the C<startdir> option and
calls C<Cwd::getcwd> anyways).

If this directory is found to exist already, the module C<croak>s.
(This shouldn't happen, but it's conceivably possible, and it's not
necessarily a bug in F<MNI::Startup>.  For instance, some previous run
of your program might not have properly cleaned up after itself, or
there might be another program with the same name and temporary
directory naming scheme that didn't clean up after itself.  Both of
these, of course, assume that the previous run of the ill-behaved progam
just happened to have the same process ID as the current run of your
program---hence, the small chance of this happening.)

Note that the directory is I<not> created, because the user might
override it with the C<-tmpdir> command-line option.  See
C<MNI::FileUtilities::check_output_dirs> for a safe and convenient way
to create output directories such as C<$TmpDir>.

On shutdown, F<MNI::Startup> will clean up this temporary directory for
you by running C<rm -rf> on it.  See L<"CLEANUP"> for details.

=item C<$KeepTmp> (C<-keeptmp>/C<-cleanup>) (initialized to: 0)

Can be used to disable cleaning up temporary files.  This, along with
several other conditions, is used by F<MNI::Startup> on program shutdown
to determine whether or not to cleanup C<$TmpDir>.  You might also use
it in your program if you normally delete some temporary files along the
way; if the user puts C<-keeptmp> on the command line (thus setting
C<$KeepTmp> true), you could respect this by not deleting anything so
that all temporary files are preserved at the end of your program's run.

=back

=head2 Option table

F<Getopt::Tabular> is a module for table-driven command line parsing; to
make the global variables just described easily customizable by the end
user, F<MNI::Startup> provides a snippet of an option table in
C<@DefaultArgs> that you include in your main table for
F<Getopt::Tabular>.  For example:

   use Getopt::Tabular;
   use MNI::Startup qw(optvars opttable);       # redundant, but what the heck
     ...
   my @opt_table = 
     (@DefaultArgs,                             # from MNI::Startup
      # rest of option table
     );

This provides five boolean options (C<-verbose>, C<-execute>, C<-clobber>,
C<-debug>, and C<-keeptmp>) along with one string option (C<-tmpdir>)
corresponding to the six variables described above.

=head1 RUNNING TIME

F<MNI::Spawn> can keep track of the CPU time used by your program and any
child processes, and by the system on behalf of them.  If the C<cputimes>
option is true, it will do just this and print out the CPU times used on
program shutdown---but only if the $Verbose global is also true and the
program is exiting successfully (i.e. with a zero exit status).

=head1 SIGNAL HANDLING

Finally, F<MNI::Spawn> can install a signal handler for the most
commonly encountered signals.  This handler prints a message describing
the signal we were hit by, cleans up (see L<"CLEANUP"> below),
uninstalls itself, and then re-sends the same signal to the current
process (i.e., your program).  The effect of this is that the signal
will I<not> be caught this time, so your program will terminate
abnormally just as though F<MNI::Startup>'s signal handler had never
been there.  The main advantage of this is that whichever program ran
your program can examine its termination status and determine that it
was indeed killed by a signal, rather than by C<exit>ing normally.

The signals handled fall into three groups: those you might normally
expect to encounter (HUP, INT, QUIT, PIPE and TERM); those that indicate
a serious problem with your script or the Perl interpreter running it
(ILL, TRAP, ABRT, IOT, BUS, EMT, FPE, SEGV, and SYS); and user-defined
signals (USR1 and USR2).  Note that not all of these signals are valid
on a given platform, so F<MNI::Startup> only installs handlers for the
subset of these signals that Perl knows about.  (With versions of Perl
previous to 5.004, this information is not available, so F<MNI::Startup>
in that case installs handlers for the five "expected" signals only.)
Currently, no distinction is made between the various groups of signals.

The F<sigtrap> module provided with Perl 5.004 provides a more flexible
approach to signal handling, but doesn't provide a signal handler to
clean up your temporary directory.  If you wish to use F<MNI::Spawn>'s
signal handler with F<sigtrap>'s more flexible interface, just specify
C<\&MNI::Startup::catch_signal> as your signal handler to F<sigtrap>.
Be sure that you also include C<nosig> in F<MNI::Startup>'s import list,
to disable its signal handling.  (The version of F<sigtrap> distributed
with Perl 5.003 and earlier isn't nearly as flexible, so there's not
much advantage in using F<sigtrap> over F<MNI::Startup>'s signal
handling unless you're running Perl 5.004 or later.)

=cut


# &startup is where we actually "do some work", i.e. set all the global
# variables that we exported up in `import'.  It's a separate subroutine
# (called by import) because it has to be done *after* import is called,
# and import isn't called until the module has been require'd
# (i.e. compiled and run).

sub startup
{
   # We set $ProgramDir and $ProgramName regardless of the options in the
   # import list because $ProgramName is needed for the temp dir name and
   # various handy messages to the user.  Likewise for $StartDir and
   # $StartDirName -- $StartDir is needed by self_announce and to cleanup
   # safely (if $TmpDir is a relative path), so we always set it too.  The
   # `progname' and `startdir' options only control whether these variables
   # are exported into the user's namespace, which is controlled by `import'
   # above.

   ($ProgramDir,$ProgramName) = $0 =~ m|^(.*/)?([^/]*)$|;
   $ProgramDir = '' unless defined $ProgramDir;

   # We need to find the starting directory if the 'startdir' option is
   # true, OR if we're going to need it later to make $TmpDir absolute.
   # The latter is true when the TMPDIR environment variable is defined
   # but not an absolute path.

   if ($options{startdir} ||
       ($ENV{'TMPDIR'} && substr ($ENV{'TMPDIR'}, 0, 1) ne '/'))
   {
      # This little trickery lets us get away with not 'use'ing Cwd --
      # we make Carp export its symbols into Cwd at compile-time, but
      # don't load Cwd.pm unless it's definitely needed.  This can 
      # shave a few tenths of a second off the overhead of using
      # MNI::Startup.

      BEGIN { package Cwd; import Carp; }
      require Cwd;

      # Note that if the cwd on startup is '/', $StartDirName will be
      # undefined.  This makes sense to me, as there is simply no
      # "trailing name" component in '/' -- we can't just pretend it's
      # there but empty (like with a missing directory component).

      $StartDir = Cwd::getcwd ();
      $StartDir .= '/' unless substr ($StartDir, -1, 1) eq '/';
      ($StartDirName) = $StartDir =~ m|/([^/]+)/$|;
   }

   if ($options{optvars})
   {
      $Verbose = 1;
      $Execute = 1;
      $Clobber = 0;
      $Debug = 0;

      my $basetmp;

      if (defined($ENV{'TMPDIR'})) {
	$basetmp = $ENV{'TMPDIR'};
      } elsif ( -d '/usr/tmp' ) {
	$basetmp = '/usr/tmp';
      } elsif ( -d '/var/tmp' ) {
	$basetmp = '/var/tmp';
      } elsif ( -d '/tmp' ) {
	$basetmp = '/tmp';
      }

      $basetmp = $StartDir . $basetmp unless substr ($basetmp, 0, 1) eq '/';
      $basetmp .= '/' unless substr ($basetmp, -1, 1) eq '/';
      $TmpDir = ($basetmp . "${ProgramName}_$$/");
      croak "$ProgramName: temporary directory $TmpDir already exists"
         if -e $TmpDir;
      $orig_tmpdir = $TmpDir;
      $KeepTmp = 0;
   }

   if ($options{opttable})
   {
      @DefaultArgs =
         (['Basic behaviour options', 'section'],
          ['-verbose|-quiet', 'boolean', 0, \$Verbose, 
           'print status information and command lines of subprograms ' .
           '[default; opposite is -quiet]' ],
          ['-execute', 'boolean', 0, \$Execute, 
           'actually execute planned commands [default]'],
          ['-clobber', 'boolean', 0, \$Clobber,
           'blithely overwrite files (and make subprograms do as well) ' .
           '[default: -noclobber]'],
          ['-debug', 'boolean', 0, \$Debug,
           'spew lots of debugging info (and make subprograms do so as well)' .
           ' [default: -nodebug]'],
          ['-tmpdir', 'string', 1, \$TmpDir,
           'set the temporary working directory'],
          ['-keeptmp|-cleanup', 'boolean', 0, \$KeepTmp,
           'don\'t delete temporary files when finished ' .
           '[default: -nokeeptmp]']);
   }

   if ($options{cputimes})
   {
      @start_times = times;
   }

   if ($options{sig})
   {
      my ($sig, @known_signals);
      @known_signals = 
         $] >= 5.004 
            ? grep (exists $SIG{$_}, keys %signals)
            : qw(HUP INT QUIT PIPE TERM);

      foreach $sig (@known_signals)
      {
         $SIG{$sig} = \&catch_signal;
      }
   }

}  # &startup


=head1 CLEANUP

From the kernel's point-of-view, there are only two ways in which a
process terminates: normally and abnormally.  Programmers generally
further distinguish between two kinds of normal termination, namely
success and failure.  In Perl, success is usually indicated by calling
C<exit> or by running off the end of the main program; failure is
indicated by calling C<exit> with a non-zero argument or C<die> outside
of any C<eval> (an uncaught exception).  Abnormal termination is what
happens when we are hit by a signal, whether it's caused internally
(e.g. a segmentation violation or floating-point exception) or
externally (such as the user hitting Ctrl-C or another process sending
the C<TERM> signal).

Regardless of how your program terminates, F<MNI::Startup> steps in to
perform some cleaning up.  In particular, it attempts to run C<rm -rf>
on the temporary directory originally named by C<$TmpDir>, but only if
the C<cleanup> option is true, the C<$KeepTmp> global is false, and the
temporary directory actually exists.  Note that if you change C<$TmpDir>
(or if the end-user changes it with the C<-tmpdir> command-line option),
then F<MNI::Startup> will I<not> clean up the new value of C<$TmpDir>.
(However, if you use the original value of C<$TmpDir> for some files and
then change its value and write new stuff in the new directory, then the
original directory will be cleaned up---just not the new one.)  The
rationale for this behaviour is that if the user (or the programmer)
goes to the trouble of specifying a custom temporary directory, they
probably want the files in it to last longer than your program's current
execution.

=cut

# Now comes the chain of subroutines by which we clean up the mess made
# by the user's program in its temporary directory ($TmpDir).  There are
# really only two kinds of shutdown to worry about: normal and abnormal.
# Normal exits are triggered by running off the end of main, calling
# exit anywhere, or die anywhere outside of an eval; these are all
# handled by the "END" block -- on shutting down the script, Perl
# executes this END block, which calls cleanup; we then return to Perl's
# shutdown sequence (including possibly any other END blocks).  Abnormal
# exits are triggered by signals; we catch a generous helping of signals
# with &catch_signal, which prints a message to say what signal killed
# us, calls &cleanup (to emulate the END block), uninstalls itself, and
# sends the same signal again to ensure that our parent knows we were
# killed by a signal.

sub cleanup
{
   my ($crash) = @_;

   # Only print times if $Verbose is true (end-user control), 'cputimes'
   # option is true (programmer control), and we're not crashing (just
   # dumb luck)

   if ($Verbose && $options{cputimes} && !$crash)
   {
      my (@stop_times, @elapsed, $i, $user, $system);

      @stop_times = times;
      foreach $i (0 .. 3)
      { 
	 $elapsed[$i] = $stop_times[$i] - $start_times[$i];
      }
      $user = $elapsed[0] + $elapsed[2];
      $system = $elapsed[1] + $elapsed[3];
      print "Elapsed time in ${ProgramName} ($$) and children:\n";
      printf "%g sec (user) + %g sec (system) = %g sec (total)\n", 
	      $user, $system, $user+$system;
   }

   if ($options{cleanup} && !$KeepTmp && 
       defined $orig_tmpdir && -d $orig_tmpdir)
   {
      local $?;                         # so we don't clobber exit status!
      system 'rm', '-rf', $orig_tmpdir;
      warn "\"rm -rf $orig_tmpdir\" failed\n" if $?;
   }
}


sub catch_signal
{
   my $sig = shift;

   $SIG{$sig} = 'IGNORE';             # in case of multiple signals under BSD
   warn "$ProgramName: $signals{$sig}\n";
   cleanup (1);
   $SIG{$sig} = 'DEFAULT';            # so we really do commit suicide
   kill $sig, $$;
}

END 
{
#    warn $?
#       ? "$ProgramName: exiting with non-zero exit status\n"
#       : "$ProgramName: exiting normally\n";
   cleanup ($?);
}


=head1 SUBROUTINES

In addition to the startup/shutdown services described above,
F<MNI::Startup> also provides a couple of subroutines that are handy in
many applications.  These subroutines will be exported into your
program's namespace if the C<subs> option is true (as always, the
default); if you instead supply C<nosubs> in F<MNI::Startup>'s import
list, they will of course still be available as
C<MNI::Startup::self_announce> and C<MNI::Startup::backgroundify>.

=over 4

=item self_announce ([LOG [, PROGRAM [, ARGS [, FORCE]]]])

Conditionally prints a brief description of the program's execution
environment: user, host, start directory, date, time, progam name, and
program arguments.  LOG, if supplied, should be a filehandle reference
(i.e., either a GLOB ref, an C<IO::Handle> (or descendants) object, or a
C<FileHandle> object); it defaults to C<\*STDOUT>.  PROGRAM should be the
program name; it defaults to C<$0>.  ARGS should be a reference to the
program's list of arguments; it defaults to C<\@ARGV>.  (Thus, to ensure
that C<self_announce> prints an accurate record, you should never fiddle
with C<$0> or C<@ARGV> in your program---the former is made unnecessary by
F<MNI::Startup>'s creation and export of C<$ProgramName>, and the latter
can be avoided without much trouble.  The three-argument form of
C<Getopt::Tabular::GetOptions>, in particular, is designed to help you
avoid clobbering C<@ARGV>.)

In general, you should put a call to C<self_announce> somewhere in your
program after all arguments have been validated, so you know that you're
not going to crash immediately.  If your program calls C<backgroundify>,
it's not necessary to also call C<self_announce> in the same run, as
C<backgroundify> calls C<self_announce>.  Thus, in programs that put
themselves into the background, you might see code like this:

   $background ? backgroundify ($logfile) : self_announce;

It shouldn't be necessary to put conditions on the call to
C<self_announce> (as was the case in versions of the MNI Perl Library up
to 0.04).  That's because there are (currently) two conditions that will
cause C<self_announce> to suppress its announcement for you. (You can
always override this and force it to print its message by supplying a
true value for FORCE.)

First, if LOG is a tty, C<self_announce> will return without doing
anything.  That is, your program's output must be redirected to a file
or pipe for the announcement to be made.  This prevents pointlessly
cluttering the display in an interactive run, but gives the user a
record of exactly what command he ran to generate a particular log file
(and the associated results).  (The assumption here is that if a
program's output is important enough to log, it's important to know the
exact command executed.  If the user didn't bother to log the output, he
probably just ran the program from a shell, and can get back the command
used anyways.)

Second, if the environment variable C<suppress_announce> is set to a
true value, no announcement will be printed.  This variable is normally
set by the F<MNI::Spawn> module; when C<Spawn> considers it unnecessary
for its child program (the program that eventually calls
C<self_announce>) to print out its arguments, then it will set this
environment variable.  The assumption here is that if C<Spawn> already
printed out the program name and arguments, and the program's output is
not being redirected elsewhere, then it's not necessary for the child to
replicate this information.  See L<MNI::Spawn> for full details.  If
C<self_announce> does not find C<suppress_announce> in its environment,
then it is naturally treated as false.  If it is found, it is deleted,
so as not to affect other programs that might be called by your program.
(Of course, if you use F<MNI::Spawn>, then C<suppress_announce> will be
set all over again.  It's only if you don't use F<MNI::Spawn> to run
your child programs that this matters.)

Again, you can override the "is it a tty?" or "is C<suppress_announce>
set?" shenanigans by simply setting FORCE to true.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : self_announce
#@INPUT      : $log     - [optional] filehandle to print announcement
#                         to; defaults to \*STDOUT
#              $program - [optional] program name to print instead of $0
#              $args    - [list ref; optional] program arguments to print
#                         instead of @ARGV
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Prints the user, host, time, and full command line (as
#              supplied in @$args).  Useful for later figuring out
#              what happened from a log file.
#@METHOD     : 
#@GLOBALS    : $0, @ARGV
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub self_announce
{
   require MNI::MiscUtilities;
   my ($log, $program, $args, $force) = @_;

   croak "self_announce: if supplied, \$log must be an open filehandle"
      if defined $log && ! (ref $log && defined fileno($log));

   $log = \*STDOUT unless defined $log;
   $program = $0 unless defined $program;
   $args = \@ARGV unless defined $args;

   # don't do it if it would go to a terminal (unless we're forced to)
   my $suppress = $ENV{'suppress_announce'};
   delete $ENV{'suppress_announce'};
   return 
      if (-t fileno ($log) || $suppress) && !$force;
         

   printf $log ("[%s] [%s] running:\n", 
                MNI::MiscUtilities::userstamp (undef, undef, $StartDir),
                MNI::MiscUtilities::timestamp ());
   print $log "  $program " . MNI::MiscUtilities::shellquote (@$args) . "\n\n";
}


=item backgroundify (LOG [, PROGRAM [, ARGS]])

Redirects C<STDOUT> and C<STDERR> to a log file and detaches to the
background by forking off a child process.  LOG must be either a
filehandle (represented by a glob reference, or an F<IO::Handle> (or
descendents) object) or a filename; if the former, it is assumed that
the file was opened for writing, and C<STDOUT> and C<STDERR> are
redirected to that file.  If LOG is not a reference, it is assumed to be
a filename to be opened for output.  You can supply a filename in the
form of the second argument to C<open>, i.e. with C<'E<gt>'> or
C<'E<gt>E<gt>'> already prepended.  If you just supply a bare filename,
C<backgroundify> will either clobber or append, depending on the value
of the C<$Clobber> global.  C<backgroundify> will then redirect
C<STDOUT> and C<STDERR> both to this file.  PROGRAM and ARGS are the
same as for C<self_annouce>; in fact, they are passed to
C<self_announce> after redirecting C<STDOUT> and C<STDERR> so that your
program will describe its execution in its own log file.  (Thus, it's
never necessary to call both C<self_announce> and C<backgroundify> in
the same run of a program.)

After redirecting, C<backgroundify> unbuffers both C<STDOUT> and
C<STDERR> (so that messages to both streams will wind up in the same
order as they are output by your program, and also to avoid problems
with unflushed buffers before forking) and C<fork>s.  If the C<fork>
fails, the parent C<die>s; otherwise, the parent C<exit>s and the child
returns 1.

Be careful about calling C<backgroundify> if you have any C<END> blocks
in your program: the C<END> block will run in both the parent and the
child, and it will run in the parent concurrently with C<backgroundify>
returning to your program as the child process.  This would be a bad
thing if, say, the C<END> block run by the parent cleans up a temporary
directory used by the child.  C<backgroundify> takes measures to ensure
that this doesn't happen with the C<END> block supplied by
F<MNI::Startup> and used for cleanup, but for you're on your own for any
other C<END> blocks in your program (or any in other modules that you
might use).

Note that C<backgroundify> is I<not> sufficient for forking off a daemon
process.  This requires a slightly different flavour of wizardry, which
is well outside the scope of this module and this man page.  Anyways,
glorified shell scripts probably shouldn't be made into daemons.

=cut

# ------------------------------ MNI Header ----------------------------------
#@NAME       : backgroundify
#@INPUT      : $log     - either a filename or filehandle
#              $program - [optional] name of program to announce; default $0
#              $args    - [list ref; optional] list of arguments to announce
#                         with $program; defaults to @ARGV
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Redirects STDOUT and STDERR to $log, forks, and (in the 
#              parent) exits.  Returns 1 to newly forked child process 
#              on success; dies on any error.  (No errors are possible
#              after the fork, so only the parent process will die.)
#
#              This is *not* sufficient for writing a daemon.
#@METHOD     : 
#@GLOBALS    : $0, @ARGV, STDOUT, STDERR
#              $Verbose, $Clobber
#@CALLS      : self_announce
#@CREATED    : 1997/07/28, GPW (loosely based on code from old JobControl.pm)
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub backgroundify
{
   my ($log, $program, $args) = @_;
   my ($stdout, $log_existed);

   # XXX to emulate what happens when a shell puts something in 
   # the BG, should we be be calling setpgrp or something???

   select STDERR; $| = 1;
   select STDOUT; $| = 1;

   # First, figure out what the nature of $log is.  We assume that if it's
   # a reference, it must be a filehandle in some form.  

   if (ref $log)                        # probably a filehandle or something
   {
      croak "backgroundify: if supplied, \$log must be an open filehandle " .
            "or a filename"
         unless defined fileno ($log);
      carp "backgroundify: \$log should not be connected to a TTY"
         if -t fileno ($log);

      $stdout = '>&=' . fileno ($log);
      print "$ProgramName: redirecting output " .
            "and detaching to background\n"
         if $Verbose;
   }
   elsif ($log)                         # assume it's a filename
   {
      if ($log =~ /^>/)                 # user already supplied clobber 
         { $stdout = $log }             # or append notation
      else                              # else, we have to figure it out
         { $stdout = ($Clobber ? '>' : '>>') . $log }
         
      $log_existed = -e $log;
      print "$ProgramName: redirecting output to $log " .
            "and detaching to background\n"
         if $Verbose;
   }
   else
   {
      croak "backgroundify: \$log must be a filehandle (glob ref) or filename";
   }

   # First save the current destination of stdout and stderr; they will be
   # restored in the parent, in case the `exit' we do there causes any
   # output.  (This can be important, because the user might have END
   # blocks in his program that will -- if he's not careful -- be executed
   # by both the parent and the child.  Restoring stdout and stderr before
   # we `exit' might help this sort of mistake get caught.)

   local (*SAVE_STDOUT, *SAVE_STDERR);
   open (SAVE_STDOUT, ">&STDOUT") || die "couldn't save STDOUT: $!\n";
   open (SAVE_STDERR, ">&STDERR") || die "couldn't save STDERR: $!\n";

   # Now redirect stdout and stderr.  We do this before forking (thus
   # necessitating the save-and-restore code) because redirection is more
   # likely to cause errors than forking, and we want any such error
   # messages to appear on the original stderr (for immediate visibility)
   # rather than in the log file if at all possible.

   unless (open (STDOUT, $stdout))
   {
      die "$ProgramName: detachment to background failed: couldn't redirect stdout to \"$stdout\" ($!)\n";
   }
   unless (open (STDERR, ">&STDOUT"))
   {
      die "$ProgramName: detachment to background failed: couldn't redirect stderr into stdout ($!)\n";
   }

   my $pid = fork;
   die "$ProgramName: detachment to background failed: couldn't fork: $!\n"
      unless defined $pid;

   if ($pid)                            # in the parent (old process)?
   {
      @options{'cputimes','cleanup'} = (); # disable normal shutdown sequence
      open (STDOUT, ">&SAVE_STDOUT") || die "couldn't restore STDOUT: $!\n";
      open (STDERR, ">&SAVE_STDERR") || die "couldn't restore STDERR: $!\n";
      exit;                             # and exit
   }

   # Now, we're in the child (new process) -- reset the "time used"
   # counters, start a new process group (to emulate what the shells do
   # when forking a child), print "self announcement" to (redirected)
   # stdout, and carry on as usual

   @start_times = times
      if ($options{'cputimes'});
   setpgrp;
   self_announce (\*STDOUT, $program, $args, 1);

   return 1;                            # return OK in new process

}  # backgroundify

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
