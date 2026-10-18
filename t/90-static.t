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
    my $src = do { local $/ = undef; <$fh> };
    close $fh or die $!;

    unlike( $src, qr/\bsystem\s*\(/, "no system(): $f" );
    unlike( $src, qr/qx\b|`/,        "no backticks/qx: $f" );
    unlike( $src, qr/\bxhost\b/,     "no xhost: $f" );
    unlike( $src, qr/-ac\b/,         "no -ac: $f" );
    unlike( $src, qr/\bopenssl\b/,   "no openssl dependency: $f" );
    unlike(
        $src,
        qr/xauth\s+(?:-f|add|remove|extract|merge|list)\b/,
        "no xauth subprocess: $f"
    );
    unlike( $src, qr/permit nopass/,    "no doas.conf edits: $f" );
    unlike( $src, qr/Xsunaba-display-/, "no /tmp lock files: $f" );
    unlike(
        $src,
        qr/-listen\s+tcp|tcp\s+listen/,
        "TCP listen never enabled: $f"
    );

    # OpenBSD::Pledge::pledge(@promises) takes a list and adds stdio
    # itself; one space-joined string is not the documented interface
    # (it only worked because the module rejoins the arguments).
    unlike(
        $src,
        qr/OpenBSD::Pledge::pledge\s*\(\s*['"][^'"]*\s[^'"]*['"]\s*\)/,
        "pledge called with a promise list, not a space-joined string: $f"
    );
}

# Privilege transition is explicit and verified in the helper
open my $fh, '<', $helper or die $!;
my $src = do { local $/ = undef; <$fh> };
close $fh or die $!;
like( $src, qr/\$\) = "\$gid \$gid"/,    'supplementary groups reset' );
like( $src, qr/setgid\(\$gid\)/,         'setgid before setuid' );
like( $src, qr/setuid\(\$uid\)/,         'setuid to target account' );
like( $src, qr/getuid\(\)\s*==\s*\$uid/, 'uid transition verified' );
like( $src, qr/setuid\(0\)\s*==\s*0\s+and\s+return/, 'no privilege regain' );
like( $src, qr/-noreset/,                            'Xephyr -noreset used' );
like( $src, qr/-nolisten/,                           'Xephyr -nolisten used' );
like( $src, qr/-resizeable/,   'Xephyr -resizeable used' );
like( $src, qr/-no-host-grab/, 'Xephyr -no-host-grab used' );
like(
    $src,
    qr/getuid\(\)\s*==\s*0\s*&&\s*geteuid\(\)\s*==\s*0/,
    'root required'
);
like(
    $src,
    qr/exec \{\s*\$opts->\{app\}\s*\}/,
    'application exec avoids the shell (indirect-object form)'
);
like( $src, qr/SOCKET_MODE/, 'socket mode restricted' );
like( $src, qr/umask\s+077/, 'umask 077 for session data' );
like( $src, qr/\buseradd\b/, 'amnesiac account creation present' );
like( $src, qr/\buserdel\b/, 'amnesiac account deletion present' );
like( $src, qr/pkill/,       'uid-bounded process cleanup present' );

# The reaper turns readdir()/account-file data into pathnames while
# running under -T, so the values must be captured to clear taint.
like(
    $src,
    qr/sub stale_session_tokens/,
    'reaper session-name filter is a capture-based helper'
);
like(
    $src,
    qr/stale_session_tokens\( readdir /,
    'reaper filters session names through stale_session_tokens'
);

# flock(2) locks are shared across fork(2); the exec'd children must
# close the helper's lock descriptors or they keep the locks for the
# whole session.
like( $src, qr/close \$lock\b/,          'display lock closed in the child' );
like( $src, qr/close \$am->\{lock_fh\}/, 'liveness lock closed in children' );

# Check executability before invoking doas; the launcher must stay unpledged
# because it needs to execute the privilege boundary itself.
{
    open my $ffh, '<', $front or die $!;
    my $fsrc = do { local $/ = undef; <$ffh> };
    close $ffh or die $!;

    # These needles are source text, not interpolated Perl.
    my $exec_at = index( $fsrc, 'exec $DOAS_BIN, $HELPER, @argv' );
    my $x_at    = index( $fsrc, '-x $DOAS_BIN' );
    ok(
        $x_at >= 0 && $exec_at > $x_at,
        'frontend checks doas before execution'
    );
    unlike(
        $fsrc,
        qr/OpenBSD::Pledge::pledge\(qw\(stdio exec\)\)/,
        'frontend does not install the removed execution promise'
    );
}

# Documentation references
for my $doc ( "$root/README.md", "$root/man/Xsunaba.1" ) {
    open my $dh, '<', $doc or die $!;
    my $text = do { local $/ = undef; <$dh> };
    close $dh or die $!;
    like( $text, qr/_xsunaba_app/, "dedicated app account documented: $doc" );
    like( $text, qr/_xsunaba_xephyr/,
        "dedicated Xephyr account documented: $doc" );
    like( $text, qr/permit nopass/, "doas rule documented: $doc" );
    like( $text, qr/--amnesiac/,    "amnesiac mode documented: $doc" );
    like(
        $text,
        qr/-resizeable|Fl resizeable/,
        "resizable Xephyr documented: $doc"
    );
    like(
        $text,
        qr/-no-host-grab|Fl no-host-grab/,
        "input fix documented: $doc"
    );
    like(
        $text,
        qr/Crossing the Unix-user isolation boundary/,
        "precise boundary wording documented: $doc"
    );
}

done_testing;
