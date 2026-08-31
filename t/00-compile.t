#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

my @checks = (
    [ "$FindBin::Bin/../bin/Xsunaba.pl",       '' ],
    [ "$FindBin::Bin/../libexec/xsunaba-helper", '-T' ],
);

for my $check (@checks) {
    my ( $file, $flags ) = @$check;
    my $cmd = "perl $flags -c $file 2>&1";
    my $out = `$cmd`;
    is( $? >> 8, 0, "compiles: $file" )
      or diag($out);
    unlike( $out, qr/compilation errors/i, "no syntax diagnostics: $file" );
}

done_testing;
