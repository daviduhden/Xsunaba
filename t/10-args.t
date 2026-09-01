#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

require "$FindBin::Bin/../libexec/xsunaba-helper";

my $parse = \&Xsunaba::Helper::parse_args;

sub ok_args {
    my ( $label, @argv ) = @_;
    my $opts = eval { $parse->(@argv) };
    ok( $opts, $label ) or diag($@);
    return $opts;
}

sub bad_args {
    my ( $label, @argv ) = @_;
    my $opts = eval { $parse->(@argv) };
    ok( !$opts, $label );
    return $opts;
}

my $base =
  [ '--parent-display', ':0', '--parent-xauth', '/home/user/.Xauthority' ];

# Minimal valid invocation
my $o = ok_args( 'minimal args', @$base, '--', '/usr/bin/xterm' );
is( $o->{display},         32, 'default display' );
is( $o->{width},           1024, 'default width' );
is( $o->{height},          768, 'default height' );
is( $o->{parent_display},  ':0', 'parent display' );
is( $o->{parent_xauth},    '/home/user/.Xauthority', 'parent xauth' );
is( $o->{app},             '/usr/bin/xterm', 'app path' );
is_deeply( $o->{app_args}, [], 'no app args' );
is_deeply( $o->{unveil},   [], 'no unveil' );
ok( !$o->{verbose}, 'not verbose' );

# Full valid invocation
$o = ok_args(
    'full args',
    '--parent-display', ':0.0',
    '--parent-xauth',   '/tmp/weird/.Xauthority',
    '--display',        '50',
    '--width',          '1280',
    '--height',         '900',
    '--unveil',         '/tmp:rwc,/etc:r',
    '--amnesiac',
    '--verbose',
    '--',
    '/usr/local/bin/firefox',
    '--private-window',
);
is( $o->{display}, 50, 'display parsed' );
is( $o->{width},   1280, 'width parsed' );
is( $o->{height},  900, 'height parsed' );
is_deeply( $o->{unveil}, [ '/tmp:rwc', '/etc:r' ], 'unveil parsed' );
ok( $o->{amnesiac}, 'amnesiac parsed' );
ok( $o->{verbose}, 'verbose parsed' );
is( $o->{app}, '/usr/local/bin/firefox', 'app parsed' );
is_deeply( $o->{app_args}, ['--private-window'], 'app args parsed' );

$o = ok_args( 'amnesiac off by default', @$base, '--', '/bin/true' );
ok( !$o->{amnesiac}, 'amnesiac defaults to off' );

# App arguments that look like helper options must be accepted
$o = ok_args(
    'dash args after --',
    @$base, '--', '/usr/bin/echo', '--display', '--verbose', '-x',
);
is_deeply( $o->{app_args}, [ '--display', '--verbose', '-x' ],
    'helper options after -- are app args' );

# Rejections
bad_args( 'no app', @$base, '--' );
bad_args( 'no separator', @$base );
bad_args( 'unknown option', @$base, '--bogus', '1', '--', '/bin/true' );
bad_args( 'missing value', @$base, '--display', '--', '/bin/true' );
bad_args( 'relative app', @$base, '--', 'xterm' );
bad_args( 'app with NUL', @$base, '--', "/bin/true\0x" );
bad_args( 'arg with NUL', @$base, '--', '/bin/true', "bad\0arg" );
bad_args( 'too many app args', @$base, '--', '/bin/true',
    ( map { "a$_" } 1 .. 260 ) );
bad_args( 'parent display host form', '--parent-display', 'host:0',
    '--parent-xauth', '/tmp/a', '--', '/bin/true' );
bad_args( 'parent display localhost', '--parent-display', 'localhost:0',
    '--parent-xauth', '/tmp/a', '--', '/bin/true' );
bad_args( 'parent display empty', '--parent-display', '',
    '--parent-xauth', '/tmp/a', '--', '/bin/true' );
bad_args( 'parent display huge', '--parent-display', ':123456',
    '--parent-xauth', '/tmp/a', '--', '/bin/true' );
bad_args( 'relative parent xauth', '--parent-display', ':0',
    '--parent-xauth', '.Xauthority', '--', '/bin/true' );
bad_args( 'parent xauth NUL', '--parent-display', ':0',
    '--parent-xauth', "/tmp/a\0b", '--', '/bin/true' );
bad_args( 'parent xauth too long', '--parent-display', ':0',
    '--parent-xauth', '/' . 'a' x 5000, '--', '/bin/true' );
bad_args( 'display zero', @$base, '--display', '0', '--', '/bin/true' );
bad_args( 'display too big', @$base, '--display', '1000', '--', '/bin/true' );
bad_args( 'display with colon', @$base, '--display', ':32', '--',
    '/bin/true' );
bad_args( 'display negative', @$base, '--display', '-1', '--', '/bin/true' );
bad_args( 'display text', @$base, '--display', 'abc', '--', '/bin/true' );
bad_args( 'width zero', @$base, '--width', '0', '--', '/bin/true' );
bad_args( 'width too big', @$base, '--width', '32768', '--', '/bin/true' );
bad_args( 'width negative', @$base, '--width', '-5', '--', '/bin/true' );
bad_args( 'width text', @$base, '--width', '1x1', '--', '/bin/true' );
bad_args( 'height zero', @$base, '--height', '0', '--', '/bin/true' );
bad_args( 'height too big', @$base, '--height', '99999', '--', '/bin/true' );
bad_args( 'unveil without perm', @$base, '--unveil', '/tmp', '--',
    '/bin/true' );
bad_args( 'unveil bad perm', @$base, '--unveil', '/tmp:z', '--',
    '/bin/true' );
bad_args( 'unveil perm with colon', @$base, '--unveil', '/a:b:c', '--',
    '/bin/true' );
bad_args( 'unveil relative path', @$base, '--unveil', 'tmp:r', '--',
    '/bin/true' );
bad_args( 'unveil empty path', @$base, '--unveil', ':r', '--', '/bin/true' );
bad_args( 'unveil too many entries', @$base,
    '--unveil', join( ',', map { "/p$_" . ':r' } 1 .. 70 ),
    '--', '/bin/true' );
bad_args( 'missing parent display', '--parent-xauth', '/tmp/a', '--',
    '/bin/true' );
bad_args( 'missing parent xauth', '--parent-display', ':0', '--',
    '/bin/true' );

# Cookie and session values must not be accepted through arguments
bad_args( 'no cookie option', @$base, '--cookie', 'cafe', '--',
    '/bin/true' );
bad_args( 'no session option', @$base, '--session', '/var/run/x', '--',
    '/bin/true' );
bad_args( 'no uid option', @$base, '--uid', '0', '--', '/bin/true' );

done_testing;
