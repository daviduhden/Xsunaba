#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

require "$FindBin::Bin/../libexec/xsunaba-helper";

# Variables the invoking user might have that must never reach the
# children (the controlled variables DISPLAY, XAUTHORITY, HOME, USER,
# LOGNAME, SHELL and PATH are verified separately below).
my @forbidden = qw(
  DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK SSH_AGENT_PID GPG_AGENT_INFO
  WAYLAND_DISPLAY XDG_SESSION_ID XDG_SESSION_TYPE KRB5CCNAME
  SESSION_MANAGER XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
  XSUNABA_UNVEIL XSUNABA_PLEDGE XSUNABA_DISPLAY
  WIDTH HEIGHT VERBOSE AUDIOCOOKIE AUDIOSOCK
);

my %dirty = (
    ( map { $_ => "hostile-value-$_" } @forbidden ),
    TERM   => 'xterm',
    TZ     => 'Europe/Madrid',
    LANG   => 'C.UTF-8',
    LC_ALL => '',
    DISPLAY   => ':0',
    HOME      => '/home/user',
    USER      => 'user',
    LOGNAME   => 'user',
    SHELL     => '/bin/ksh',
    PATH      => '/evil/bin',
);
my $passthru = Xsunaba::Helper::_passthrough( \%dirty );

my $env = Xsunaba::Helper::build_app_env(
    display     => ':32',
    xauthority  => '/var/run/xsunaba/s/app/client-auth',
    home        => '/home/_xsunaba_app',
    username    => '_xsunaba_app',
    shell       => '/bin/ksh',
    runtime_dir => '/var/run/xsunaba/s/app/run',
    passthru    => $passthru,
);

my @expected = qw(
  PATH HOME USER LOGNAME SHELL DISPLAY XAUTHORITY
  XDG_RUNTIME_DIR TERM TZ LANG
);
my @keys = sort keys %$env;
is_deeply( \@keys, [ sort @expected ], 'app environment is exactly the whitelist' );

is( $env->{DISPLAY},    ':32', 'app DISPLAY is the nested display' );
is( $env->{XAUTHORITY}, '/var/run/xsunaba/s/app/client-auth',
    'app XAUTHORITY is its own client-auth' );
is( $env->{HOME}, '/home/_xsunaba_app', 'app HOME is the sandbox home' );
is( $env->{USER}, '_xsunaba_app', 'app USER is the sandbox account' );
is( $env->{LOGNAME}, '_xsunaba_app', 'app LOGNAME is the sandbox account' );
is( $env->{XDG_RUNTIME_DIR}, '/var/run/xsunaba/s/app/run',
    'runtime dir is session private' );
is( $env->{TZ}, 'Europe/Madrid', 'TZ passed through' );
ok( !exists $env->{LC_ALL}, 'empty passthrough values dropped' );
ok( !exists $env->{DISPLAY} || $env->{DISPLAY} ne ':0',
    'parent display never in app environment' );

for my $v (@forbidden) {
    ok( !exists $env->{$v}, "forbidden variable absent: $v" );
}

# Xephyr environment: only the parent display and its extracted
# authority file, nothing else.
$env = Xsunaba::Helper::build_xephyr_env(
    display    => ':0',
    xauthority => '/var/run/xsunaba/s/xephyr/parent-auth',
    home       => '/var/run/xsunaba/s/xephyr',
    passthru   => $passthru,
);
@keys = sort keys %$env;
is_deeply( \@keys, [ sort qw(PATH HOME DISPLAY XAUTHORITY TERM TZ LANG) ],
    'Xephyr environment is minimal' );
is( $env->{DISPLAY}, ':0', 'Xephyr DISPLAY is the parent display' );
is( $env->{XAUTHORITY}, '/var/run/xsunaba/s/xephyr/parent-auth',
    'Xephyr gets only the extracted parent authority' );
ok( $env->{XAUTHORITY} ne '/var/run/xsunaba/s/app/client-auth',
    'Xephyr never receives the application authority' );
ok( !exists $env->{XDG_RUNTIME_DIR}, 'no runtime dir for Xephyr' );
for my $v (@forbidden) {
    ok( !exists $env->{$v}, "forbidden variable absent (Xephyr): $v" );
}

done_testing;
