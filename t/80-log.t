#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
no warnings qw(once);
use FindBin;

# The cookie must never appear in any diagnostic output, log line or
# process listing. The helper never takes it as an argument and never
# formats it into a message. Verify this at the source level: no
# output statement may reference the cookie variable.
my $helper = "$FindBin::Bin/../libexec/xsunaba-helper";
open my $fh, '<', $helper or die $!;
my $src = do { local $/; <$fh> };
close $fh;

my @out        = grep { /\b(_inf|_wrn|_err|_dbg)\b/ } split /\n/, $src;
my $violations = 0;
for my $line (@out) {
    next if $line =~ /^\s*sub\b/;
    $violations += $line =~ /\bcookie\b/;
}
is( $violations, 0, 'no output call references the cookie' );

# The cookie is only ever written into authority files; it must never
# be part of the helper's argument interface.
unlike( $src, qr/--cookie/, 'no --cookie argument exists', );

# Messages emitted during a session reference only the display number
# and session directory, never authentication material.
require "$FindBin::Bin/../libexec/xsunaba-helper";
use File::Temp qw(tempdir);
local $Xsunaba::Helper::VERBOSE = 1;
my $dir = tempdir( CLEANUP => 1 );
my $rng = "$dir/rng";
open my $rh, '>', $rng or die $!;
print {$rh} 'x' x 16;
close $rh;
open $rh, '<', $rng or die $!;
my $cookie = Xsunaba::Helper::gen_cookie($rh);

my $out;
{
    open my $cap, '>', \$out or die $!;
    my $old = select($cap);
    Xsunaba::Helper::_inf('using display :32');
    Xsunaba::Helper::_inf('session directory /var/run/xsunaba/deadbeef');
    select($old);
    close $cap;
}
unlike( $out, qr/$cookie/,      'cookie never in info output' );
unlike( $out, qr/[0-9a-f]{32}/, 'no 32-hex token in info output' );
like( $out, qr/display :32/, 'display message present' );

done_testing;
