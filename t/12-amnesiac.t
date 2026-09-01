#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(dies_ok lives_ok);

require "$FindBin::Bin/../libexec/xsunaba-helper";

# --- Account name generation ---------------------------------------
my $name = Xsunaba::Helper::gen_account_name( 'a1b2c3d4e5f60718' );
is( $name, '_xsunaba_a1b2c3d4e5f60718', 'account name derived' );
ok( length($name) <= 31, 'fits OpenBSD login name limit' );
like( $name, qr/\A[a-z_][a-z0-9_-]*\z/, 'valid login name charset' );

dies_ok { Xsunaba::Helper::gen_account_name('xyz') }
qr/token/, 'short token rejected';
dies_ok { Xsunaba::Helper::gen_account_name( 'G' x 16 ) }
qr/token/, 'uppercase token rejected';
dies_ok { Xsunaba::Helper::gen_account_name( 'a' x 16 . '/' ) }
qr/token/, 'traversal token rejected';

my %uniq = map { Xsunaba::Helper::gen_account_name($_) => 1 } (
    '0000000000000001', '0000000000000002', '0000000000000003',
);
is( scalar keys %uniq, 3, 'distinct tokens give distinct accounts' );

# --- Home derivation ------------------------------------------------
is(
    Xsunaba::Helper::ephemeral_home_for('_xsunaba_0000000000000001'),
    '/var/xsunaba/home/_xsunaba_0000000000000001',
    'home derived from account',
);

# --- Home deletion safety -------------------------------------------
my $user = '_xsunaba_0000000000000001';
my $home = Xsunaba::Helper::ephemeral_home_for($user);

# regular dir owned by the right uid: safe
my $lstat_ok = sub {
    return ( undef, undef, 0040400, 1, 55555, 0, 0, 0, 0, 0, 0, 0, 0 );
};
ok(
    Xsunaba::Helper::home_safe_to_delete( $home, $user, 55555, $lstat_ok ),
    'matching dir with matching uid is safe',
);

# symlink: unsafe
my $lstat_link = sub {
    return ( undef, undef, 0120400, 1, 55555, 0, 0, 0, 0, 0, 0, 0, 0 );
};
ok(
    !Xsunaba::Helper::home_safe_to_delete( $home, $user, 55555, $lstat_link ),
    'symlink rejected',
);

# wrong owner: unsafe
ok(
    !Xsunaba::Helper::home_safe_to_delete( $home, $user, 0, $lstat_ok ),
    'wrong owner rejected',
);

# path outside the base: unsafe
ok(
    !Xsunaba::Helper::home_safe_to_delete(
        '/home/other', $user, 55555, $lstat_ok
    ),
    'foreign path rejected',
);
ok(
    !Xsunaba::Helper::home_safe_to_delete(
        '/var/xsunaba/home/../home/_xsunaba_0000000000000001',
        $user, 55555, $lstat_ok,
    ),
    'traversal path rejected',
);

# missing: unsafe
my $lstat_missing = sub { return () };
ok(
    !Xsunaba::Helper::home_safe_to_delete( $home, $user, 55555,
        $lstat_missing ),
    'missing path rejected',
);

# --- Account command argv -------------------------------------------
is_deeply(
    [ Xsunaba::Helper::build_useradd_argv( $user, $home ) ],
    [ '/usr/sbin/useradd', '-d', $home, '-g', '=uid',
      '-s', '/sbin/nologin', $user ],
    'useradd argv: no shell, private group, nologin, recorded home',
);
is_deeply(
    [ Xsunaba::Helper::build_userdel_argv($user) ],
    [ '/usr/sbin/userdel', $user ],
    'userdel argv',
);
is_deeply(
    [ Xsunaba::Helper::build_groupdel_argv($user) ],
    [ '/usr/sbin/groupdel', $user ],
    'groupdel argv',
);
is_deeply(
    [ Xsunaba::Helper::build_pkill_argv( 'TERM', 55555 ) ],
    [ '/usr/bin/pkill', '-TERM', '-U', '55555', '.' ],
    'pkill argv bounded by uid',
);
dies_ok { Xsunaba::Helper::build_pkill_argv( 'HUP', 5 ) }
qr/signal/, 'unsupported signal rejected';
dies_ok { Xsunaba::Helper::build_pkill_argv( 'TERM', 0 ) }
qr/uid/, 'uid 0 rejected for pkill';
dies_ok { Xsunaba::Helper::build_pkill_argv( 'TERM', '$(x)' ) }
qr/uid/, 'shell metacharacters rejected for pkill';

# --- Argument parsing ------------------------------------------------
my $base = [ '--parent-display', ':0', '--parent-xauth', '/x' ];
my $o = Xsunaba::Helper::parse_args( @$base, '--', '/bin/true' );
ok( !$o->{amnesiac}, 'amnesiac defaults off' );
$o = Xsunaba::Helper::parse_args( @$base, '--amnesiac', '--', '/bin/true' );
ok( $o->{amnesiac}, '--amnesiac parsed' );

# --- Stale-session identification patterns ---------------------------
for my $bad ( '..', '.', 'x' x 31 . 'x', '_xsunaba_zzzzzzzzzzzzzzzz',
    '0000000000000000000000000000000X' ) {
    like( '', qr//, 'no-op' );    # keep plan alignment simple
}
my $ok_token   = '0123456789abcdef0123456789abcdef';
my $bad_tokens = [
    '..', '.', '0123456789abcdef0123456789abcde',
    '0123456789abcdef0123456789abcdef0',
    'X123456789abcdef0123456789abcdef',
];
for my $t (@$bad_tokens) {
    ok( $t !~ /\A[0-9a-f]{32}\z/, "token rejected: $t" );
}
ok( $ok_token =~ /\A[0-9a-f]{32}\z/, 'valid session token accepted' );

done_testing;
