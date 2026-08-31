package TestHelper;

use strict;
use warnings;
use Exporter qw(import);
use Test::More;

our @EXPORT_OK = qw(dies_ok lives_ok);

sub dies_ok (&;@) {
    my ( $code, @rest ) = @_;
    my $re   = @rest ? shift @rest : undef;
    my $name = @rest ? shift @rest : 'code dies as expected';
    my $ok = !eval { $code->(); 1 };
    my $err = $@ || '';
    ok( $ok, $name );
    like( $err, $re, "$name: error matches" ) if $re;
    return $err;
}

sub lives_ok (&;@) {
    my ( $code, @rest ) = @_;
    my $re   = @rest ? shift @rest : undef;
    my $name = @rest ? shift @rest : 'code lives as expected';
    my $ok = eval { $code->(); 1 };
    my $err = $@ || '';
    ok( $ok, $name ) or diag($err);
    like( $err, $re, "$name: error matches" ) if $re && !$ok;
    return $ok;
}

1;
