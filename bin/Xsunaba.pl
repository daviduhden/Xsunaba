#!/usr/bin/perl

package Xsunaba;

use strict;
use warnings;
use File::Basename;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(pledge unveil unveil_lock sandbox launch);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

our $PLEGE_PROMISES = 'stdio rpath wpath cpath fattr proc exec inet dns unix tty';

my $UNVEIL_LOCKED = 0;

sub _color {
	my ($code, $msg) = @_;
	(-t STDOUT) ? "\e[${code}m${msg}\e[0m" : $msg;
}

sub _dbg { warn "[Xsunaba] @_\n" if $ENV{VERBOSE} || $ENV{XSUNABA_VERBOSE} }
sub _inf { print _color("1;32", "[INFO]") . " @_\n" if $ENV{VERBOSE} }
sub _wrn { print STDERR _color("1;33", "[WARN]") . " @_\n" }
sub _err { print STDERR _color("1;31", "[ERROR]") . " @_\n" }

sub pledge {
	my ($promises) = @_;
	$promises //= $PLEGE_PROMISES;
	unless ($^O eq 'openbsd') { _dbg "pledge: not on OpenBSD"; return }
	require OpenBSD::Pledge;
	OpenBSD::Pledge::pledge($promises)
	  or _wrn "pledge($promises): $!";
}

sub unveil {
	my ($path, $perm) = @_;
	$perm //= 'r';
	unless ($^O eq 'openbsd') { _dbg "unveil: not on OpenBSD"; return }
	return _dbg("unveil($path): already locked") if $UNVEIL_LOCKED;
	require OpenBSD::Unveil;
	OpenBSD::Unveil::unveil($path, $perm);
}

sub unveil_lock {
	unless ($^O eq 'openbsd') { _dbg "unveil_lock: not on OpenBSD"; return }
	return if $UNVEIL_LOCKED;
	require OpenBSD::Unveil;
	OpenBSD::Unveil::unveil();
	$UNVEIL_LOCKED = 1;
}

sub sandbox {
	my %opts = @_;

	$PLEGE_PROMISES = $ENV{XSUNABA_PLEDGE}
	  if exists $ENV{XSUNABA_PLEDGE};

	my @unveil_entries;
	if (exists $opts{unveil}) {
		@unveil_entries =
		  ref $opts{unveil} eq 'ARRAY' ? @{ $opts{unveil} } : $opts{unveil};
	} elsif ($ENV{XSUNABA_UNVEIL}) {
		@unveil_entries = split /\s*,\s*/, $ENV{XSUNABA_UNVEIL};
	}

	for my $entry (@unveil_entries) {
		next unless $entry;
		my ($path, $perm) = split /:/, $entry, 2;
		unveil($path, $perm // 'r');
	}

	unveil_lock() if @unveil_entries && !exists $opts{lock};

	my $pstr = exists $opts{pledge} ? $opts{pledge} : $PLEGE_PROMISES;
	pledge($pstr) if defined $pstr && $pstr ne '';

	return unless $opts{app};
	my @args = @{ $opts{args} // [] };
	exec $opts{app}, @args or die "exec: $!";
}

sub launch {
	my %opts = @_;

	my $display   = $opts{display} // $ENV{XSUNABA_DISPLAY} // ':32';
	my $width     = $opts{width}   // $ENV{WIDTH}          // 1024;
	my $height    = $opts{height}  // $ENV{HEIGHT}         // 768;
	my $home      = $ENV{HOME} or die "HOME not set";
	my $xauth_f   = "$home/.Xauthority-xsunaba";
	my $sockets   = "/tmp/.X11-unix";
	my $app       = $opts{app} or die "No application specified";
	my @app_args  = @{ $opts{args} // [] };

	my $openssl = '/usr/bin/openssl';
	my $xauth   = '/usr/X11R6/bin/xauth';
	my $xephyr  = '/usr/X11R6/bin/Xephyr';

	my $full_app = join(" ", $app, @app_args);

	# --- Launcher unveil (not locked: child will extend + lock) ---
	if ($^O eq 'openbsd') {
		eval {
			require OpenBSD::Unveil;
			OpenBSD::Unveil::unveil($_, 'rx')
			  for ($openssl, $xauth, $xephyr, '/bin/sh');
			OpenBSD::Unveil::unveil($_, 'r')
			  for ('/etc', '/dev');
			OpenBSD::Unveil::unveil($_, 'rwc')
			  for ($home, '/tmp', $sockets);
		};
	}

	# --- Generate cookie ---
	my $cookie = `$openssl rand -hex 16`;
	chomp $cookie;

	# --- Find unused display ---
	for my $i (32 .. 99) {
		if (!-e "$sockets/X$i") {
			$display = ":$i";
			last;
		}
	}
	_inf "using display $display";

	# --- Geometry hacks for known browsers ---
	my $base = basename($app);
	if ($base eq 'chrome') {
		$full_app .= " -window-size=${width},${height} --window-position=0,0";
	} elsif ($base eq 'firefox') {
		$full_app .= " -width $width -height $height";
	}

	# --- Add auth cookie for the Xephyr display ---
	system("$xauth -f $xauth_f add $display . $cookie") == 0
	  or do { _err "failed to add auth cookie"; return; };

	# --- Start Xephyr ---
	my $xephyr_pid = fork();
	die "fork: $!" unless defined $xephyr_pid;

	if ($xephyr_pid == 0) {
		$ENV{DISPLAY} = '';
		exec("$xephyr -auth $xauth_f -screen ${width}x${height}"
			  . " -br -nolisten tcp $display");
		die "exec Xephyr: $!";
	}

	_inf "Xephyr started (PID $xephyr_pid)";
	sleep 3;

	kill(0, $xephyr_pid)
	  or do { _err "Xephyr failed to start"; return; };

	# --- User-configured unveil entries for the app ---
	my @app_unveil;
	if (exists $opts{unveil}) {
		@app_unveil =
		  ref $opts{unveil} eq 'ARRAY' ? @{ $opts{unveil} } : $opts{unveil};
	} elsif ($ENV{XSUNABA_UNVEIL}) {
		@app_unveil = split /\s*,\s*/, $ENV{XSUNABA_UNVEIL};
	}

	my $app_pledge = $opts{pledge} // $ENV{XSUNABA_PLEDGE}
	  // $PLEGE_PROMISES;

	# --- Launch the application ---
	my $app_pid = fork();
	die "fork: $!" unless defined $app_pid;

	if ($app_pid == 0) {
		$ENV{DISPLAY} = $display;

		if ($^O eq 'openbsd') {
			eval {
				require OpenBSD::Unveil;
				require OpenBSD::Pledge;

				# Child inherits parent's unveiled paths.
				# Add app-specific paths and lock.
				for my $entry (@app_unveil) {
					next unless $entry;
					my ($path, $perm) = split /:/, $entry, 2;
					OpenBSD::Unveil::unveil($path,
						$perm // 'r');
				}

				# Ensure X11 socket + devices reachable
				OpenBSD::Unveil::unveil($sockets, 'rwc');
				OpenBSD::Unveil::unveil('/dev',    'r');

				OpenBSD::Unveil::unveil();

				OpenBSD::Pledge::pledge($app_pledge)
				  or die "pledge: $!";
			};
		}

		exec($full_app);
		die "exec $app: $!";
	}

	_inf "launched '$app' (PID $app_pid)";

	# --- Pledge the launcher's own remaining surface ---
	if ($^O eq 'openbsd') {
		eval {
			require OpenBSD::Pledge;
			OpenBSD::Pledge::pledge(
				'stdio rpath wpath cpath fattr proc exec')
			  or _wrn "launcher pledge: $!";
		};
	}

	# --- Wait for the application to exit ---
	waitpid($app_pid, 0);

	# --- Stop Xephyr ---
	_inf "stopping Xephyr (PID $xephyr_pid)";
	if (kill(0, $xephyr_pid)) {
		kill('TERM', $xephyr_pid);
		sleep 1;
		kill('KILL', $xephyr_pid) if kill(0, $xephyr_pid);
	}

	# --- Remove auth cookies ---
	system("$xauth -f $xauth_f remove $display");
	_inf "cleanup complete";
}

package main;

unless (caller) {
	$ENV{XSUNABA_VERBOSE} ||= $ENV{VERBOSE} // '';

	@ARGV or die "Usage: Xsunaba [command args...]\n";

	Xsunaba::launch(
		app  => $ARGV[0],
		args => [ @ARGV[ 1 .. $#ARGV ] ],
	);
}

1;
