#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;

require "$FindBin::Bin/../libexec/xsunaba-helper";

# Socket path derivation
is( Xsunaba::Helper::socket_path(32),
    '/tmp/.X11-unix/X32', 'socket path for display 32' );
is( Xsunaba::Helper::socket_path(0),
    '/tmp/.X11-unix/X0', 'socket path for display 0' );

# Free display selection
my $found = Xsunaba::Helper::find_free_display(
    32, sub { 0 },
);
is( $found, 32, 'first display free' );

$found = Xsunaba::Helper::find_free_display(
    32,
    sub { $_[0] == 32 || $_[0] == 33 ? 1 : 0 },
);
is( $found, 34, 'skips taken displays' );

$found = Xsunaba::Helper::find_free_display(
    32, sub { 1 },
);
is( $found, undef, 'no free display' );

# Existence probe semantics
my $dir = tempdir( CLEANUP => 1 );
is( Xsunaba::Helper::path_exists("$dir/missing"), 0, 'missing path' );
is( Xsunaba::Helper::path_exists($dir), 1, 'existing path' );

# Session directory creation: random, private, under run dir
local $Xsunaba::Helper::RUN_DIR = "$dir/run";
mkdir $Xsunaba::Helper::RUN_DIR or die $!;
my %sessions;
for ( 1 .. 5 ) {
    my $s = Xsunaba::Helper::make_session_dir();
    like( $s, qr{\A\Q$Xsunaba::Helper::RUN_DIR\E/[0-9a-f]{32}\z},
        'session path is random hex under run dir' );
    my @st = stat $s;
    is( $st[2] & 0777, 0711, 'session dir mode 0711' );
    ok( !$sessions{$s}++, 'session path unique' );
}

# Exit status mapping
is( Xsunaba::Helper::exit_status(0),     0,   'exit 0' );
is( Xsunaba::Helper::exit_status(5 << 8), 5,  'exit 5' );
is( Xsunaba::Helper::exit_status(0x0009), 137, 'killed by signal 9' );
is( Xsunaba::Helper::exit_status(-1),    1,   'unknown status' );

done_testing;
