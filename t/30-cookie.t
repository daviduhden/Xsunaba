#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(dies_ok lives_ok);

require "$FindBin::Bin/../libexec/xsunaba-helper";

my $dir = tempdir( CLEANUP => 1 );

sub rng_file {
    my ($bytes) = @_;
    my $path = "$dir/rng-" . int( rand 100000 ) . ".bin";
    open my $fh, '>', $path or die $!;
    print {$fh} $bytes;
    close $fh;
    open my $rfh, '<', $path or die $!;
    return $rfh;
}

# Cookie format
my $fh = rng_file( join '', map { chr( int rand 256 ) } 1 .. 32 );
my $cookie = Xsunaba::Helper::gen_cookie($fh);
like( $cookie, qr/\A[0-9a-f]{32}\z/, 'cookie is 32 lowercase hex chars' );

# Uniqueness across many draws
my %seen;
for ( 1 .. 200 ) {
    my $h = rng_file( join '', map { chr( int rand 256 ) } 1 .. 32 );
    my $c = Xsunaba::Helper::gen_cookie($h);
    $seen{$c} = 1;
}
is( scalar keys %seen, 200, 'cookies are unique across draws' );

# Short reads fail closed
my $short = rng_file('abc');
dies_ok { Xsunaba::Helper::gen_cookie($short) }
qr/short read/, 'short random read rejected';

# A cookie from one draw must never equal a later draw's value
my $h1 = rng_file( 'a' x 16 );
my $h2 = rng_file( 'b' x 16 );
isnt(
    Xsunaba::Helper::gen_cookie($h1),
    Xsunaba::Helper::gen_cookie($h2),
    'different entropy yields different cookies',
);

done_testing;
