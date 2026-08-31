#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

my $root   = "$FindBin::Bin/..";
my $helper = "$root/libexec/xsunaba-helper";
my $front  = "$root/bin/Xsunaba.pl";

for my $f ( $helper, $front ) {
    open my $fh, '<', $f or die $!;
    my $src = do { local $/; <$fh> };
    close $fh;

    unlike( $src, qr/\bsystem\s*\(/,        "no system(): $f" );
    unlike( $src, qr/qx\b|`/,               "no backticks/qx: $f" );
    unlike( $src, qr/\bxhost\b/,            "no xhost: $f" );
    unlike( $src, qr/-ac\b/,                "no -ac: $f" );
    unlike( $src, qr/\bopenssl\b/,          "no openssl dependency: $f" );
    unlike( $src, qr/xauth\s+(?:-f|add|remove|extract|merge|list)\b/,
        "no xauth subprocess: $f" );
    unlike( $src, qr/permit nopass/,        "no doas.conf edits: $f" );
    unlike( $src, qr/Xsunaba-display-/,     "no /tmp lock files: $f" );
    unlike( $src, qr/-listen\s+tcp|tcp\s+listen/,
        "TCP listen never enabled: $f" );
}

# Privilege transition is explicit and verified in the helper
open my $fh, '<', $helper or die $!;
my $src = do { local $/; <$fh> };
close $fh;
like( $src, qr/\$\) = "\$gid \$gid"/, 'supplementary groups reset' );
like( $src, qr/setgid\(\$gid\)/,       'setgid before setuid' );
like( $src, qr/setuid\(\$uid\)/,       'setuid to target account' );
like( $src, qr/getuid\(\)\s*==\s*\$uid/, 'uid transition verified' );
like( $src, qr/setuid\(0\)\s*==\s*0\s+and\s+return/, 'no privilege regain' );
like( $src, qr/-noreset/,              'Xephyr -noreset used' );
like( $src, qr/-nolisten/,             'Xephyr -nolisten used' );
like( $src, qr/getuid\(\)\s*==\s*0\s*&&\s*geteuid\(\)\s*==\s*0/,
    'root required' );
like( $src, qr/SOCKET_MODE/,           'socket mode restricted' );

# Documentation references
for my $doc ( "$root/README.md", "$root/man/Xsunaba.1" ) {
    open my $dh, '<', $doc or die $!;
    my $text = do { local $/; <$dh> };
    close $dh;
    like( $text, qr/_xsunaba_app/,    "dedicated app account documented: $doc" );
    like( $text, qr/_xsunaba_xephyr/, "dedicated Xephyr account documented: $doc" );
    like( $text, qr/permit nopass/,   "doas rule documented: $doc" );
}

done_testing;
