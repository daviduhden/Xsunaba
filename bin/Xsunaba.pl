#!/usr/bin/perl

package Xsunaba;

use strict;
use warnings;
use File::Basename;
use File::Temp qw(tempfile);
use Exporter   qw(import);
use Fcntl      qw(O_CREAT O_RDWR LOCK_EX LOCK_NB);

our @EXPORT_OK   = qw(pledge unveil unveil_lock sandbox launch);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

our $PLEDGE_PROMISES =
  'stdio rpath wpath cpath fattr proc exec' . ' inet dns unix tty';

my $UNVEIL_LOCKED = 0;

sub _color {
    my ( $code, $msg ) = @_;
    ( -t STDOUT ) ? "\e[${code}m${msg}\e[0m" : $msg;
}

sub _dbg {
    warn "[Xsunaba] @_\n"
      if $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE};
}
sub _inf { print _color( "1;32", "[INFO]" ) . " @_\n" if $ENV{VERBOSE} }
sub _wrn { print STDERR _color( "1;33", "[WARN]" ) . " @_\n" }
sub _err { print STDERR _color( "1;31", "[ERROR]" ) . " @_\n" }

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
    if     ($UNVEIL_LOCKED) {
        _wrn "unveil($path): already locked";
        return;
    }

    # Preload both XS modules before the filesystem view can be locked, so a
    # later low-level pledge() call does not need to resolve module files.
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

    if ( $^O eq 'openbsd' ) {
        require OpenBSD::Unveil;
    }

    my $display = $opts{display} // $ENV{XSUNABA_DISPLAY} // ':32';
    my $width   = $opts{width}   // $ENV{WIDTH}           // 1024;
    my $height  = $opts{height}  // $ENV{HEIGHT}          // 768;
    $ENV{HOME}    or die "HOME not set";
    $ENV{DISPLAY} or die "DISPLAY not set";
    $width  =~ /\A[1-9][0-9]*\z/ or die "Invalid width '$width'";
    $height =~ /\A[1-9][0-9]*\z/ or die "Invalid height '$height'";
    my $sockets  = "/tmp/.X11-unix";
    my $app      = $opts{app} or die "No application specified";
    my @app_args = @{ $opts{args} // [] };

    my $openssl = '/usr/bin/openssl';
    my $xauth   = '/usr/X11R6/bin/xauth';
    my $xephyr  = '/usr/X11R6/bin/Xephyr';

    # --- Generate cookie ---
    open my $cookie_fh, '-|', $openssl, 'rand', '-hex', '16'
      or die "openssl: $!";
    my $cookie = <$cookie_fh> // '';
    close $cookie_fh or die "openssl rand failed";
    chomp $cookie;
    $cookie =~ /\A[[:xdigit:]]{32}\z/
      or die "openssl returned an invalid X11 cookie";

    # --- Find unused display ---
    $display =~ /\A:(\d+)\z/
      or die "Invalid display '$display' (expected :number)";
    my $start_display = $1;
    my $found_display;
    my $display_lock_fh;
    for my $i ( $start_display .. 99 ) {
        next if -e "$sockets/X$i";
        my $lock_path = "/tmp/.Xsunaba-display-$<-$i.lock";
        sysopen( my $candidate_lock, $lock_path, O_CREAT | O_RDWR, 0600 )
          or next;
        if ( flock( $candidate_lock, LOCK_EX | LOCK_NB )
            && !-e "$sockets/X$i" )
        {
            $display         = ":$i";
            $found_display   = 1;
            $display_lock_fh = $candidate_lock;
            last;
        }
        close $candidate_lock;
    }
    die "No free X display from :$start_display through :99"
      unless $found_display;
    _inf "using display $display";

    my ( $xauth_fh, $xauth_f ) =
      tempfile( 'Xsunaba-xauth-XXXXXX', DIR => '/tmp', UNLINK => 0 );
    close $xauth_fh or die "close $xauth_f: $!";

    # --- Geometry hacks for known browsers ---
    my $base = basename($app);
    if ( $base =~ /(?:^|-)chrome$/ || $base =~ /chromium/ ) {
        push @app_args, "--window-size=${width},${height}",
          '--window-position=0,0';
    }
    elsif ( $base =~ /firefox/ ) {
        push @app_args, '-width', $width, '-height', $height;
    }

    # --- Add auth cookie for the Xephyr display ---
    system( $xauth, '-f', $xauth_f, 'add', $display, '.', $cookie ) == 0
      or do {
        unlink $xauth_f;
        die "xauth failed to add the cookie";
      };

    # --- Start Xephyr ---
    my $xephyr_pid = fork();
    unless ( defined $xephyr_pid ) {
        unlink $xauth_f;
        die "fork: $!";
    }

    if ( $xephyr_pid == 0 ) {
        exec $xephyr, '-auth', $xauth_f, '-screen', "${width}x${height}",
          '-br', '-nolisten', 'tcp', $display;
        die "exec Xephyr: $!";
    }

    _inf "Xephyr started (PID $xephyr_pid)";
    sleep 3;

    unless ( kill( 0, $xephyr_pid ) ) {
        waitpid( $xephyr_pid, 0 );
        unlink $xauth_f or _wrn "cannot remove $xauth_f: $!";
        _err "Xephyr failed to start";
        return 1;
    }

    # --- User-configured unveil entries for the app ---
    my @app_unveil;
    if ( exists $opts{unveil} ) {
        @app_unveil =
          ref $opts{unveil} eq 'ARRAY' ? @{ $opts{unveil} } : $opts{unveil};
    }
    elsif ( $ENV{XSUNABA_UNVEIL} ) {
        @app_unveil = split /\s*,\s*/, $ENV{XSUNABA_UNVEIL};
    }

    # --- Launch the application ---
    my $app_pid = fork();
    unless ( defined $app_pid ) {
        kill 'TERM', $xephyr_pid;
        waitpid( $xephyr_pid, 0 );
        unlink $xauth_f;
        die "fork: $!";
    }

    if ( $app_pid == 0 ) {
        $ENV{DISPLAY}    = $display;
        $ENV{XAUTHORITY} = $xauth_f;

        if ( $^O eq 'openbsd' && @app_unveil ) {
            require OpenBSD::Unveil;
            for my $entry (@app_unveil) {
                next unless $entry;
                my ( $path, $perm ) = split /:/, $entry, 2;
                OpenBSD::Unveil::unveil( $path, $perm // 'r' )
                  or die "unveil($path): $!";
            }
            OpenBSD::Unveil::unveil( $sockets, 'rw' )
              or die "unveil($sockets): $!";
            OpenBSD::Unveil::unveil( $xauth_f, 'r' )
              or die "unveil($xauth_f): $!";
            OpenBSD::Unveil::unveil()
              or die "unveil lock: $!";
        }

        exec {$app} $app, @app_args;
        die "exec $app: $!";
    }

    _inf "launched '$app' (PID $app_pid)";

    # --- Wait for the application to exit ---
    waitpid( $app_pid, 0 );
    my $app_status = $?;

    # --- Stop Xephyr ---
    _inf "stopping Xephyr (PID $xephyr_pid)";
    if ( kill( 0, $xephyr_pid ) ) {
        kill( 'TERM', $xephyr_pid );
        sleep 1;
        kill( 'KILL', $xephyr_pid ) if kill( 0, $xephyr_pid );
    }
    waitpid( $xephyr_pid, 0 );

    unlink $xauth_f or _wrn "cannot remove $xauth_f: $!";
    _inf "cleanup complete";
    return 1                           if $app_status == -1;
    return 128 + ( $app_status & 127 ) if $app_status & 127;
    return $app_status >> 8;
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
