#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(run_capture);

my @checks = (
    [ "$FindBin::Bin/../bin/Xsunaba.pl",         '' ],
    [ "$FindBin::Bin/../libexec/xsunaba-helper", '-T' ],
);

for my $check (@checks) {
    my ( $file, $flags ) = @$check;
    my @cmd = ( $^X, ( length $flags ? $flags : () ), '-c', $file );
    my ( $stdout, $stderr, $status ) = run_capture(@cmd);
    my $out = $stdout . $stderr;
    is( $status >> 8, 0, "compiles: $file" )
      or diag($out);
    unlike( $out, qr/compilation errors/i, "no syntax diagnostics: $file" );
}

done_testing;
