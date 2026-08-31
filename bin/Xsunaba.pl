#!/usr/bin/perl

package Xsunaba;

use strict;
use warnings;
use File::Basename;
use Exporter   qw(import);

our @EXPORT_OK   = qw(pledge unveil unveil_lock sandbox launch);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

our $PLEDGE_PROMISES =
  'stdio rpath wpath cpath fattr proc exec' . ' inet dns unix tty';

# Locations of the privileged session helper and doas. Overridable
# only by code embedding this module (for example tests), never
# through the environment.
our $DOAS_BIN = '/usr/bin/doas';
our $HELPER   = '/usr/local/libexec/xsunaba-helper';

our $MAX_DISPLAY = 999;

my $UNVEIL_LOCKED = 0;

sub _dbg {
    warn "[Xsunaba] @_\n"
      if $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE};
}

sub _wrn { print STDERR "[WARN] @_\n" }

sub pledge {
    my ($promises) = @_;
    $promises //= $PLEDGE_PROMISES;
    unless ( $^O eq 'openbsd' ) { _dbg "pledge: not on OpenBSD"; return 1 }
    require OpenBSD::Pledge;
    my @promises = grep { length } split /\s+/, $promises;
    return 1 unless @promises;
    return OpenBSD::Pledge::pledge(@promises);
}

sub unveil {
    my ( $path, $perm ) = @_;
    $perm //= 'r';
    unless ( $^O eq 'openbsd' ) { _dbg "unveil: not on OpenBSD"; return 1 }
    if ($UNVEIL_LOCKED) {
        _wrn "unveil($path): already locked";
        return;
    }

    # Preload both XS modules before the filesystem view can be
    # locked, so a later low-level pledge() call does not need to
    # resolve module files.
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;
    return OpenBSD::Unveil::unveil( $path, $perm );
}

sub unveil_lock {
    unless ( $^O eq 'openbsd' ) {
        _dbg "unveil_lock: not on OpenBSD";
        return 1;
    }
    return 1 if $UNVEIL_LOCKED;
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;
    return unless OpenBSD::Unveil::unveil();
    $UNVEIL_LOCKED = 1;
    return 1;
}

sub sandbox {
    my %opts        = @_;
    my $sandbox_app = $opts{app} or die "No application specified";

    if (
        (
            exists $opts{pledge}
            && defined $opts{pledge}
            && $opts{pledge} ne ''
        )
        || ( exists $ENV{XSUNABA_PLEDGE}
            && $ENV{XSUNABA_PLEDGE} ne '' )
      )
    {
        die "XSUNABA_PLEDGE cannot restrict an exec'd program; "
          . "OpenBSD::Pledge does not expose execpromises";
    }

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
# Exported for tests. The helper re-validates every value; nothing
# here is trusted by it.
#
sub build_helper_argv {
    my (%o) = @_;
    my @argv;
    push @argv, '--parent-display', $o{parent_display};
    push @argv, '--parent-xauth',   $o{parent_xauth};
    push @argv, '--display', $o{display} if defined $o{display};
    push @argv, '--width',   $o{width}   if defined $o{width};
    push @argv, '--height',  $o{height}  if defined $o{height};
    if ( defined $o{unveil} && length $o{unveil} ) {
        push @argv, '--unveil', $o{unveil};
    }
    push @argv, '--verbose' if $o{verbose};
    push @argv, '--';
    push @argv, @{ $o{app_argv} // [] };
    return @argv;
}

sub _valid_number {
    my ( $what, $value, $max ) = @_;
    $value =~ /\A[1-9][0-9]*\z/ or die "Invalid $what '$value'";
    $value <= $max or die "$what must be in 1..$max";
    return $value;
}

sub launch {
    my %opts = @_;

    if (
        (
            exists $opts{pledge}
            && defined $opts{pledge}
            && $opts{pledge} ne ''
        )
        || ( exists $ENV{XSUNABA_PLEDGE}
            && $ENV{XSUNABA_PLEDGE} ne '' )
      )
    {
        die "XSUNABA_PLEDGE cannot restrict an exec'd program; "
          . "OpenBSD::Pledge does not expose execpromises";
    }

    my $app      = $opts{app} or die "No application specified";
    my @app_args = @{ $opts{args} // [] };

    my $display = $opts{display} // $ENV{XSUNABA_DISPLAY} // ':32';
    my $width   = $opts{width}   // $ENV{WIDTH}           // 1024;
    my $height  = $opts{height}  // $ENV{HEIGHT}          // 768;
    $ENV{HOME}    or die "HOME not set";
    $ENV{DISPLAY} or die "DISPLAY not set";

    my ($display_n) = $display =~ /\A:([0-9]{1,3})\z/
      or die "Invalid display '$display' (expected :number)";
    $display_n >= 1 && $display_n <= $MAX_DISPLAY
      or die "Display must be in 1..$MAX_DISPLAY";
    _valid_number( 'width',  $width,  32767 );
    _valid_number( 'height', $height, 32767 );

    my ($parent_display) = $ENV{DISPLAY} =~ /\A(:[0-9]{1,4}(?:\.[0-9]{1,4})?)\z/
      or die "Invalid DISPLAY '$ENV{DISPLAY}' (expected local :number)";

    my $parent_xauth = $ENV{XAUTHORITY} || "$ENV{HOME}/.Xauthority";
    $parent_xauth =~ m{\A/}
      or die "Invalid XAUTHORITY '$parent_xauth' (not absolute)";
    -f $parent_xauth or die "Cannot read Xauthority '$parent_xauth'";

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

    # Geometry hacks for known browsers.
    my $base = basename($app);
    if ( $base =~ /(?:^|-)chrome$/ || $base =~ /chromium/ ) {
        push @app_args, "--window-size=${width},${height}",
          '--window-position=0,0';
    }
    elsif ( $base =~ /firefox/ ) {
        push @app_args, '-width', $width, '-height', $height;
    }

    my @argv = build_helper_argv(
        parent_display => $parent_display,
        parent_xauth   => $parent_xauth,
        display        => $display_n,
        width          => $width,
        height         => $height,
        unveil         => $unveil,
        verbose        => ( $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE} ) ? 1 : 0,
        app_argv       => [ $app, @app_args ],
    );

    # After this point the process only needs to execute the helper;
    # fail closed if the frontend itself cannot be restricted.
    if ( $^O eq 'openbsd' ) {
        require OpenBSD::Pledge;
        OpenBSD::Pledge::pledge( 'stdio exec' )
          or die "pledge: $!";
    }

    exec $DOAS_BIN, $HELPER, @argv;
    die "exec $DOAS_BIN: $!";
}

package main;

unless (caller) {
    $ENV{XSUNABA_VERBOSE} ||= $ENV{VERBOSE} // '';

    @ARGV or die "Usage: Xsunaba [command args...]\n";

    exit Xsunaba::launch(
        app  => $ARGV[0],
        args => [ @ARGV[ 1 .. $#ARGV ] ],
    );
}

1;
