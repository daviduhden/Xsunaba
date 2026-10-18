#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

# The documented install step is `make show-doas-rule`; a stray escape
# once made it print a literal "\n" instead of a real continuation, so
# the copied rule was malformed. Verify the printed text.
my $root = "$FindBin::Bin/..";

sub run_make {
    my (@args) = @_;
    open my $fh, '-|', 'make', '-C', $root, @args or return;
    my $out    = do { local $/ = undef; <$fh> };
    my $closed = close $fh;
    return ( defined $out ? $out : '', $? );
}

my ( $probe, $probe_status ) = run_make( '-n', 'show-doas-rule' );
if ( !defined $probe || $probe_status != 0 || $probe =~ /No targets|No rule/ ) {
    plan skip_all => 'make is not available';
}

my ( $rule, $rule_status ) = run_make( '-s', 'show-doas-rule' );
is( $rule_status, 0, 'make show-doas-rule exits 0' );
my $setenv_vars = qr/TZ LANG LC_ALL LC_CTYPE LC_MESSAGES/;
like(
    $rule,
    qr/^permit nopass setenv \{ $setenv_vars \} \\$/m,
    'printed doas rule starts with the expected options'
);
like(
    $rule,
    qr/^\s*USER as root cmd \/usr\/local\/libexec\/xsunaba-helper$/m,
    'printed rule restricts cmd to the helper'
);
unlike( $rule, qr/^\s*args\b/m,
    'no fixed args restriction (doas matches the whole list exactly)' );
unlike( $rule, qr/\\n/, 'no literal backslash-n leaked into the rule' );
my @continuations = ( $rule =~ /\\$/mg );
ok( @continuations >= 1, 'rule uses real backslash-newline continuations' );

my ( $help, $help_status ) = run_make( '-s', 'help' );
is( $help_status, 0, 'make help exits 0' );
like( $help, qr/^  install-users  - /m, 'help output is aligned' );
unlike( $help, qr/^   /m, 'help output has no stray indentation' );

done_testing;
