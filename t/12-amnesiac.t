#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/lib";
use TestHelper qw(dies_ok run_capture);

## no critic (Modules::RequireBarewordIncludes)
# The helper is a script, not a module; it must be loaded by path.
require "$FindBin::Bin/../libexec/xsunaba-helper";

# The helper relies on the object interface of getpwnam/getgrnam
# (->uid, ->gid, ->dir, ->shell, ->members). Those methods only exist
# when User::pwent/User::grent have overridden the builtins; guard
# against a regression that would abort every session at startup.
my $root_pw = Xsunaba::Helper::getpwuid(0);
ok( ref($root_pw) && $root_pw->uid == 0,
    'getpwuid returns a User::pwent object (->uid works)' );
ok(
    defined $root_pw->dir && defined $root_pw->shell,
    'passwd object exposes ->dir and ->shell'
);
my $root_gr = Xsunaba::Helper::getgrgid(0);
ok( ref($root_gr) && $root_gr->gid == 0,
    'getgrgid returns a User::grent object (->gid works)' );
ok( ref( $root_gr->members ) eq 'ARRAY',
    'group object exposes ->members as an array reference' );

# --- Account name generation ---------------------------------------
my $name = Xsunaba::Helper::gen_account_name('a1b2c3d4e5f60718');
is( $name, '_xsunaba_a1b2c3d4e5f60718', 'account name derived' );
ok( length($name) <= 31, 'fits OpenBSD login name limit' );
like( $name, qr/\A[a-z_][a-z0-9_-]*\z/, 'valid login name charset' );

dies_ok { Xsunaba::Helper::gen_account_name('xyz') }
qr/token/, 'short token rejected';
dies_ok { Xsunaba::Helper::gen_account_name( 'G' x 16 ) }
qr/token/, 'uppercase token rejected';
dies_ok { Xsunaba::Helper::gen_account_name( 'a' x 16 . '/' ) }
qr/token/, 'traversal token rejected';

my %uniq = map { Xsunaba::Helper::gen_account_name($_) => 1 }
  qw(0000000000000001 0000000000000002 0000000000000003);
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
    return ( undef, undef, oct('40400'), 1, 55_555, 0, 0, 0, 0, 0, 0, 0, 0 );
};
ok(
    Xsunaba::Helper::home_safe_to_delete( $home, $user, 55_555, $lstat_ok ),
    'matching dir with matching uid is safe',
);

# symlink: unsafe
my $lstat_link = sub {
    return ( undef, undef, oct('120400'), 1, 55_555, 0, 0, 0, 0, 0, 0, 0, 0 );
};
ok(
    !Xsunaba::Helper::home_safe_to_delete( $home, $user, 55_555, $lstat_link ),
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
        '/home/other', $user, 55_555, $lstat_ok
    ),
    'foreign path rejected',
);
ok(
    !Xsunaba::Helper::home_safe_to_delete(
        '/var/xsunaba/home/../home/_xsunaba_0000000000000001', $user,
        55_555,                                                $lstat_ok,
    ),
    'traversal path rejected',
);

# missing: unsafe
my $lstat_missing = sub { return () };
ok(
    !Xsunaba::Helper::home_safe_to_delete(
        $home, $user, 55_555, $lstat_missing
    ),
    'missing path rejected',
);

# --- Account command argv -------------------------------------------
is_deeply(
    [ Xsunaba::Helper::build_useradd_argv( $user, $home ) ],
    [
        '/usr/sbin/useradd', '-d', $home,
        '-g',                '=uid',
        '-p',                '*',
        '-s',                '/sbin/nologin',
        $user,
    ],
    'useradd argv: locked password, private group, nologin, recorded home',
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
    [ Xsunaba::Helper::build_pkill_argv( 'TERM', 55_555 ) ],
    [ '/usr/bin/pkill', '-TERM', '-U', '55555', '.' ],
    'pkill argv bounded by uid',
);

# A child killed by a signal must never be reported as success: teardown
# uses the status to decide whether an account is still in use.
## no critic (Subroutines::ProtectPrivateSubs)
my $signal_status = Xsunaba::Helper::_run_cmd( $^X, '-e', 'kill 15, $$' );
is( $signal_status, 143, 'signal-terminated command is reported as failure' );
dies_ok { Xsunaba::Helper::build_pkill_argv( 'HUP', 5 ) }
qr/signal/, 'unsupported signal rejected';
dies_ok { Xsunaba::Helper::build_pkill_argv( 'TERM', 0 ) }
qr/uid/, 'uid 0 rejected for pkill';

# The metacharacters are the malicious input; they must stay literal.
dies_ok { Xsunaba::Helper::build_pkill_argv( 'TERM', '$(x)' ) }
qr/uid/, 'shell metacharacters rejected for pkill';

# --- Argument parsing ------------------------------------------------
my $base = [ '--parent-display', ':0', '--parent-xauth', '/x' ];
my $o    = Xsunaba::Helper::parse_args( @$base, '--', '/bin/true' );
ok( !$o->{amnesiac}, 'amnesiac defaults off' );
$o = Xsunaba::Helper::parse_args( @$base, '--amnesiac', '--', '/bin/true' );
ok( $o->{amnesiac}, '--amnesiac parsed' );

# --- Stale-session identification patterns ---------------------------
# The reaper accepts only 32 lowercase hex characters as session
# directory names; every other form must be rejected.
my $ok_token   = '0123456789abcdef0123456789abcdef';
my $bad_tokens = [
    '..',                              '.',
    '0123456789abcdef0123456789abcde', '0123456789abcdef0123456789abcdef0',
    'X123456789abcdef0123456789abcdef',
];
for my $t (@$bad_tokens) {
    ok( $t !~ /\A[0-9a-f]{32}\z/, "token rejected: $t" );
}
ok( $ok_token =~ /\A[0-9a-f]{32}\z/, 'valid session token accepted' );

# --- stale_session_tokens -------------------------------------------
# The reaper must return only the 32-hex directory names, and the value
# must be untainted: reap_stale_sessions() runs under -T and uses it to
# build paths and command arguments, which reject tainted strings.
my @tokens = Xsunaba::Helper::stale_session_tokens(
    '.', '..', $ok_token,
    '0123456789abcdef0123456789abcde',
    'X123456789abcdef0123456789abcdef',
    'not-a-token',
);
is_deeply( \@tokens, [$ok_token],
    'only exact 32-hex session names are returned' );
is( scalar( Xsunaba::Helper::stale_session_tokens() ),
    0, 'no names yields no tokens' );

# Taint is only observable in a -T interpreter, so probe in a child:
# run the real reaper against a synthetic, pre-crashed session. If any
# readdir()/account value leaked taint, open()/unlink() would abort.
{
    my $helper    = "$FindBin::Bin/../libexec/xsunaba-helper";
    my $dir       = tempdir( CLEANUP => 1 );
    my $probe     = "$dir/probe.pl";
    my $probe_src = <<'PROBE';
use strict;
use warnings;
my ( $helper, $rundir, $token ) = @ARGV;
# -T taints @ARGV; untaint only the values this probe needs as paths.
($helper) = $helper =~ m{\A(.+)\z};
($rundir) = $rundir =~ m{\A(.+)\z};
($token)  = $token  =~ m{\A(.+)\z};
require $helper;

no warnings 'once';
local $Xsunaba::Helper::RUN_DIR = $rundir;
my $session = "$rundir/$token";
mkdir $session or die "mkdir $session: $!\n";
open my $lf, '>', "$session/active.lock" or die "$!\n";
close $lf;
open my $af, '>', "$session/account" or die "$!\n";
print {$af} "_xsunaba_ffffffffffffffff\n";
close $af;

# This must not abort under -T (taint) and must remove the session.
Xsunaba::Helper::reap_stale_sessions();
die "session not removed\n" if -e $session;
print "REAPED\n";
PROBE
    open my $pf, '>', $probe or die $!;
    print {$pf} $probe_src or die $!;
    close $pf              or die $!;

    my ( $stdout, $stderr, $status ) =
      run_capture( $^X, '-T', $probe, $helper, $dir, $ok_token );
    my $out = $stdout . $stderr;
    is( $status >> 8,
        0, 'reaper runs and reaps under -T without taint failures' )
      or diag($out);
    like( $out, qr/REAPED/, 'reaper confirmed the synthetic session removed' );
}

done_testing;
