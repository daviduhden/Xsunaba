#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

# The documented install step is `make show-doas-rule`; a stray escape
# once made it print a literal "\n" instead of a real continuation, so
# the copied rule was malformed. Verify the printed text.
my $root = "$FindBin::Bin/..";

my $probe = `make -C "$root" -n show-doas-rule 2>&1`;
if ( $? != 0 || $probe =~ /No targets|No rule/ ) {
    plan skip_all => 'make is not available';
}

my $rule = `make -C "$root" -s show-doas-rule 2>&1`;
is( $? >> 8, 0, 'make show-doas-rule exits 0' );
like(
    $rule,
    qr/^permit nopass setenv \{ TZ LANG LC_ALL LC_CTYPE LC_MESSAGES \} \\$/m,
    'printed doas rule starts with the expected options'
);
like(
    $rule,
    qr/^\s*args --parent-display$/m,
    'printed rule contains the args restriction'
);
unlike( $rule, qr/\\n/, 'no literal backslash-n leaked into the rule' );
my @continuations = ( $rule =~ /\\$/mg );
ok( @continuations >= 2, 'rule uses real backslash-newline continuations' );

my $help = `make -C "$root" -s help 2>&1`;
is( $? >> 8, 0, 'make help exits 0' );
like( $help, qr/^  install-users  - /m, 'help output is aligned' );
unlike( $help, qr/^   /m, 'help output has no stray indentation' );

done_testing;
