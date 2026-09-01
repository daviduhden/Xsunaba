#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

require "$FindBin::Bin/../libexec/xsunaba-helper";

my @argv = Xsunaba::Helper::build_xephyr_argv(
    display     => ':32',
    width       => 1280,
    height      => 900,
    server_auth => '/var/run/xsunaba/s/xephyr/server-auth',
);

my %count;
$count{$_}++ for @argv;

is( $count{'-resizeable'},  1, 'exactly one -resizeable' );
is( $count{'-no-host-grab'}, 1, 'exactly one -no-host-grab' );
is( $count{'-nolisten'},     1, 'exactly one -nolisten' );
is( $count{'-noreset'},      1, 'exactly one -noreset' );
is( $count{'-br'},           1, 'exactly one -br' );
is( $count{'-screen'},       1, 'exactly one -screen' );
is( $count{'-auth'},         1, 'exactly one -auth' );
ok( !$count{'-ac'}, 'no -ac' );
ok( !$count{'-listen'}, 'no -listen' );
ok( !$count{'-host-cursor'}, 'no explicit -host-cursor' );

is( $argv[0], '/usr/X11R6/bin/Xephyr', 'Xephyr path first' );
my %seen;
my $last;
for my $a (@argv) {
    if ( $a =~ /\A-\w/ && $a !~ /\A-[0-9]/ ) {
        ok( !$seen{$a}++, "option $a unique" );
    }
    $last = $a;
}
is( $last, ':32', 'display is the final argument' );

# screen geometry: initial size only
my $si = 0;
$si++ while $si < @argv && $argv[$si] ne '-screen';
is( $argv[ $si + 1 ], '1280x900', '-screen carries initial geometry' );

# initial geometry must match width x height exactly
for my $geom ( [ 1024, 768, '1024x768' ], [ 640, 480, '640x480' ] ) {
    my ( $w, $h, $expect ) = @$geom;
    my @a = Xsunaba::Helper::build_xephyr_argv(
        display => ':1', width => $w, height => $h,
        server_auth => '/x',
    );
    my $i = 0;
    $i++ while $a[$i] ne '-screen';
    is( $a[ $i + 1 ], $expect, "initial geometry $w x $h" );
}

done_testing;
