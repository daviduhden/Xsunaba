#!/usr/bin/perl

package Xsunaba;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK   = qw(pledge unveil unveil_lock sandbox launch);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

# Low-level use only: a pledged caller must not execute another program
# with the current kernel ABI. The frontend does not call this wrapper.
our $PLEDGE_PROMISES =
  'stdio rpath wpath cpath fattr proc' . ' inet dns unix tty';

# Locations of the privileged session helper and doas. Overridable
# only by code embedding this module (for example tests), never
# through the environment.
our $DOAS_BIN = '/usr/bin/doas';
our $HELPER   = '/usr/local/libexec/xsunaba-helper';

our $MAX_DISPLAY = 999;

my $UNVEIL_LOCKED = 0;

# Informational logging.  Messages are enabled only when the caller sets
# VERBOSE or the legacy XSUNABA_VERBOSE variable, and always go to stdout so
# the caller can separate status from warnings and errors.
sub logi {
    print {*STDOUT} "[INFO] @_\n"
      if $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE};
    return;
}

# Emit a warning on stderr without changing the control flow.  Warnings are
# used for degraded but still safe behavior; fatal startup errors use
# die_tool().
sub logw {
    print {*STDERR} "[WARN] @_\n";
    return;
}

# Print a fatal command-line or startup error and exit with the conventional
# failure status.  Validators elsewhere die instead, so tests and embedding
# callers can catch the message.
sub die_tool {
    print {*STDERR} "[ERROR] $_[0]\n";
    exit 1;
}

# Apply a pledge(2) promise set through the OpenBSD Perl binding.  The binding
# is loaded lazily so the module can still be inspected or used on non-OpenBSD
# hosts, where the call is a logged no-op.  This wrapper is for low-level use
# only; the frontend itself must remain unpledged because it execs doas.
sub pledge {
    my ($promises) = @_;
    $promises //= $PLEDGE_PROMISES;
    unless ( $^O eq 'openbsd' ) { logi 'pledge: not on OpenBSD'; return 1 }
    require OpenBSD::Pledge;
    my @promises = grep { length } split /\s+/, $promises;
    return 1 unless @promises;
    return OpenBSD::Pledge::pledge(@promises);
}

# Restrict path visibility with unveil(2).  Both OpenBSD modules are loaded
# before the view can be locked so a later low-level pledge call never needs to
# resolve module files after the filesystem is restricted.  Once unveil_lock()
# has run, further calls are refused instead of silently ignored.
sub unveil {
    my ( $path, $perm ) = @_;
    $perm //= 'r';
    unless ( $^O eq 'openbsd' ) { logi 'unveil: not on OpenBSD'; return 1 }
    if     ($UNVEIL_LOCKED) {
        logw "unveil($path): already locked";
        return;
    }

    # Preload both XS modules before the filesystem view can be
    # locked, so a later low-level pledge() call does not need to
    # resolve module files.
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;
    return OpenBSD::Unveil::unveil( $path, $perm );
}

# Permanently lock the unveil(2) view.  The operation is idempotent and
# returns true on non-OpenBSD hosts so callers can share the same setup path.
sub unveil_lock {
    unless ( $^O eq 'openbsd' ) {
        logi 'unveil_lock: not on OpenBSD';
        return 1;
    }
    return 1 if $UNVEIL_LOCKED;
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;
    return unless OpenBSD::Unveil::unveil();
    $UNVEIL_LOCKED = 1;
    return 1;
}

#
# XSUNABA_PLEDGE is a legacy knob that cannot work: OpenBSD::Pledge has
# no binding for pledge(2)'s execpromises argument, so a promise would
# not restrict the exec'd program and would silently do nothing. Reject
# a non-empty value from either the options or the environment.
#
sub _reject_pledge {
    my ($opts) = @_;
    my $opt_pledge = exists $opts->{pledge} ? $opts->{pledge} : undef;
    if (   ( defined $opt_pledge && $opt_pledge ne '' )
        || ( exists $ENV{XSUNABA_PLEDGE} && $ENV{XSUNABA_PLEDGE} ne '' ) )
    {
        die q{XSUNABA_PLEDGE cannot restrict an exec'd program; }
          . 'OpenBSD::Pledge does not expose execpromises';
    }
}

# In-process sandbox helper for callers that want to run an application after
# applying unveil entries.  The entries are applied in order, the view is
# optionally locked, and exec replaces the process.  The helper never uses a
# shell and rejects the legacy XSUNABA_PLEDGE knob because the Perl binding
# cannot express execpromises.
sub sandbox {
    my %opts        = @_;
    my $sandbox_app = $opts{app} or die 'No application specified';

    _reject_pledge( \%opts );

    if ( $^O eq 'openbsd' ) {
        require OpenBSD::Unveil;
    }

    my @unveil_entries;
    if ( exists $opts{unveil} ) {
        @unveil_entries =
          ref $opts{unveil} eq 'ARRAY' ? @{ $opts{unveil} } : $opts{unveil};
    }
    elsif ( $ENV{XSUNABA_UNVEIL} ) {
        @unveil_entries = split /\s*,\s*/, $ENV{XSUNABA_UNVEIL};
    }

    for my $entry (@unveil_entries) {
        next unless $entry;
        my ( $path, $perm ) = split /:/, $entry, 2;
        unveil( $path, $perm // 'r' )
          or die "unveil($path): $!";
    }

    if ( @unveil_entries && ( !exists $opts{lock} || $opts{lock} ) ) {
        unveil_lock() or die "unveil lock: $!";
    }

    my @args = @{ $opts{args} // [] };
    exec {$sandbox_app} $sandbox_app, @args;
    die "exec $sandbox_app: $!";
}

#
# Build the exact argv passed to the privileged helper through doas.
# Optional values are omitted rather than sent as empty arguments, and the
# application argv is placed after the "--" separator so options cannot be
# confused with application arguments. Exported for tests; the helper
# re-validates every value and trusts nothing here.
#
sub build_helper_argv {
    my (%o) = @_;
    my @argv;
    push @argv, '--parent-display', $o{parent_display};
    push @argv, '--parent-xauth',   $o{parent_xauth};
    push @argv, '--display',        $o{display} if defined $o{display};
    push @argv, '--width',          $o{width}   if defined $o{width};
    push @argv, '--height',         $o{height}  if defined $o{height};
    if ( defined $o{unveil} && length $o{unveil} ) {
        push @argv, '--unveil', $o{unveil};
    }
    push @argv, '--amnesiac' if $o{amnesiac};
    push @argv, '--verbose'  if $o{verbose};
    push @argv, '--';
    push @argv, @{ $o{app_argv} // [] };
    return @argv;
}

# Validate a positive decimal dimension.  A leading zero or sign is rejected so
# the helper receives a canonical value in the documented range.
sub _valid_number {
    my ( $what, $value, $max ) = @_;
    $value =~ /\A[1-9][0-9]*\z/ or die "Invalid $what '$value'";
    $value <= $max              or die "$what must be in 1..$max";
    return $value;
}

#
# Resolve a bare command name through PATH to the absolute program path
# the helper requires. Names containing a slash (including absolute
# paths) are returned unchanged. Only absolute PATH entries are
# considered, and the candidate must be an executable regular file.
# Returns undef when the command cannot be resolved.
#
sub resolve_app {
    my ( $app, $path ) = @_;
    return $app if $app =~ m{/};
    $path //= $ENV{PATH};
    return unless defined $path && length $path;
    for my $dir ( split /:/, $path ) {
        next unless $dir =~ m{\A/};
        my $candidate = "$dir/$app";
        return $candidate if -f $candidate && -x _;
    }
    return;
}

# High-level launch path used by the command-line wrapper.  It validates the
# application, nested display, geometry and parent Xauthority, then execs doas
# with the helper argv.  No shell is involved.  The frontend deliberately stays
# unpledged: doas performs the privilege transition, and adding an exec promise
# would not restrict the helper.
sub launch {
    my %opts = @_;

    _reject_pledge( \%opts );

    my $app = $opts{app} or die 'No application specified';
    $app = resolve_app($app)
      // die "Cannot find executable '$opts{app}' in PATH";
    my @app_args = @{ $opts{args} // [] };

    my $display = $opts{display} // $ENV{XSUNABA_DISPLAY} // ':32';
    my $width   = $opts{width}   // $ENV{WIDTH}           // 1024;
    my $height  = $opts{height}  // $ENV{HEIGHT}          // 768;
    $ENV{HOME}    or die 'HOME not set';
    $ENV{DISPLAY} or die 'DISPLAY not set';

    my ($display_n) = $display =~ /\A:([0-9]{1,3})\z/
      or die "Invalid display '$display' (expected :number)";
    die "Display must be in 1..$MAX_DISPLAY"
      if $display_n < 1 || $display_n > $MAX_DISPLAY;
    _valid_number( 'width',  $width,  32_767 );
    _valid_number( 'height', $height, 32_767 );

    my ($parent_display) = $ENV{DISPLAY} =~ /\A(:[0-9]{1,4}(?:\.[0-9]{1,4})?)\z/
      or die "Invalid DISPLAY '$ENV{DISPLAY}' (expected local :number)";

    my $parent_xauth = $ENV{XAUTHORITY} || "$ENV{HOME}/.Xauthority";
    $parent_xauth =~ m{\A/}
      or die "Invalid XAUTHORITY '$parent_xauth' (not absolute)";
    -f $parent_xauth or die "Cannot read Xauthority '$parent_xauth'";
    -r $parent_xauth or die "Cannot read Xauthority '$parent_xauth'";

    my $unveil;
    if ( exists $opts{unveil} && defined $opts{unveil} ) {
        $unveil =
          ref $opts{unveil} eq 'ARRAY'
          ? join( ',', @{ $opts{unveil} } )
          : $opts{unveil};
    }
    elsif ( $ENV{XSUNABA_UNVEIL} ) {
        $unveil = $ENV{XSUNABA_UNVEIL};
    }

    # The browser window geometry is deliberately left to the
    # application: forced exact-fit sizes fight the resizable Xephyr
    # window and push popup anchors onto the screen edges, which is
    # where menu selection problems show up.
    my @argv = build_helper_argv(
        parent_display => $parent_display,
        parent_xauth   => $parent_xauth,
        display        => $display_n,
        width          => $width,
        height         => $height,
        unveil         => $unveil,
        amnesiac       => $opts{amnesiac}                            ? 1 : 0,
        verbose        => ( $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE} ) ? 1 : 0,
        app_argv       => [ $app, @app_args ],
    );

    # Check executability first so a missing doas fails with our own
    # message instead of Perl's "Can't exec" warning. $! is set by -x.
    -x $DOAS_BIN
      or die "exec $DOAS_BIN: $!";

    # Remain unpledged: the frontend must execute doas, which performs
    # its own privilege checks before invoking the root-owned helper.

    exec $DOAS_BIN, $HELPER, @argv;
    die "exec $DOAS_BIN: $!";
}

# Script entry point.  The module is also loadable by tests, so this block runs
# only when the file is executed directly.  The first argument selects amnesiac
# mode; the remaining argv is the application and its arguments.
unless (caller) {
    $ENV{XSUNABA_VERBOSE} ||= $ENV{VERBOSE} // '';

    my $amnesiac = 0;
    if ( @ARGV && $ARGV[0] eq '--amnesiac' ) {
        $amnesiac = 1;
        shift @ARGV;
    }

    @ARGV
      or Xsunaba::die_tool 'Usage: Xsunaba [--amnesiac] [command args...]';

    my $status = eval {
        Xsunaba::launch(
            amnesiac => $amnesiac,
            app      => $ARGV[0],
            args     => [ @ARGV[ 1 .. $#ARGV ] ],
        );
    };
    if ( my $err = $@ ) {
        $err =~ s/\s+\z//;
        print {*STDERR} "[ERROR] $err\n";
        exit 1;
    }
    exit $status;
}

1;
