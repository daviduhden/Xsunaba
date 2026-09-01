#!/usr/bin/perl

# Optional X11 integration test for the popup/pointer-grab regression
# tool. Runs only when explicitly requested:
#
#   XSUNABA_TEST_DISPLAY=:32 prove -I t/lib t/95-x11-optional.t
#
# (:32 being a running nested Xephyr server; requires the tool built
# with 'make tools' and xdotool for input automation.)
#
# Verifies: a popup with an active pointer grab receives motion and
# button events at correct coordinates, and every item can be
# clicked. This is the deterministic stand-in for the browser
# popup-menu selection bug.

use strict;
use warnings;
use Test::More;
use FindBin;

my $display = $ENV{XSUNABA_TEST_DISPLAY};
my $tool    = "$FindBin::Bin/../tools/popup-grab-test";

unless ( defined $display && length $display && -x $tool ) {
    plan skip_all =>
      'set XSUNABA_TEST_DISPLAY and build tools/ to run X11 tests';
}
my @xdotool = qw(xdotool);
my $probe = `xdotool version 2>&1`;
if ( $? != 0 ) {
    plan skip_all => 'xdotool not available';
}

my $pid = fork();
die "fork: $!" unless defined $pid;
if ( $pid == 0 ) {
    open STDIN,  '<', '/dev/null' or die $!;
    open STDOUT, '>', "$FindBin::Bin/../tools/popup-grab-test.log"
      or die $!;
    open STDERR, '>&', \*STDOUT or die $!;
    exec $tool, $display;
    exit 127;
}

sleep 2;
my $win = `xdotool search --name popup-grab-test 2>/dev/null`;
chomp $win;
if ( !length $win ) {
    kill 'KILL', $pid;
    waitpid( $pid, 0 );
    plan skip_all => 'popup-grab-test window not found on display';
}

my $ok = 1;
# click the menu bar (top 40 rows of a 640x480 window at 0,0)
$ok &&= system( @xdotool, 'mousemove', '--sync', '100', '20' ) == 0;
$ok &&= system( @xdotool, 'click', '1' ) == 0;
sleep 1;
# popup appears at x=92,y=40; click every item center
for my $i ( 0 .. 4 ) {
    my $x = 92 + 60;
    my $y = 40 + 8 + $i * 28 + 12;
    $ok &&= system( @xdotool, 'mousemove', '--sync', $x, $y ) == 0;
    $ok &&= system( @xdotool, 'click', '1' ) == 0;
    sleep 0.4;
}
ok( $ok, 'xdotool input injection succeeded' );

# the tool exits 0 only when every item received its click
my $deadline = time() + 10;
my $status;
while ( waitpid( $pid, 0 ) <= 0 ) {
    last if time() > $deadline;
}
$status = $?;

open my $fh, '<', "$FindBin::Bin/../tools/popup-grab-test.log"
  or die $!;
my $log = do { local $/; <$fh> };
close $fh;

is( $status >> 8, 0, 'popup-grab-test exited 0 (all items clicked)' );
like( $log, qr/pointer grabbed/, 'pointer grab succeeded' );
like( $log, qr/motion in popup/, 'grab received motion events' );
like( $log, qr/all items clicked/, 'all items clicked' );

done_testing;
