#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

require "$FindBin::Bin/../libexec/xsunaba-helper";

my $socket     = '/tmp/.X11-unix/X32';
my $client_auth = '/var/run/xsunaba/deadbeef/app/client-auth';
my $runtime     = '/var/run/xsunaba/deadbeef/app/run';
my $user = [ '/tmp:rwc', '/etc:r', '/usr/local/bin/firefox:rx' ];

my $entries = Xsunaba::Helper::build_unveil_entries(
    socket_path  => $socket,
    client_auth  => $client_auth,
    runtime_dir  => $runtime,
    user_entries => $user,
);

is_deeply(
    $entries,
    [ @$user, "$socket:w", "$client_auth:r", "$runtime:rwxc" ],
    'user entries plus exact socket, auth and runtime',
);

# The whole socket directory must never be exposed
ok( !( grep { $_ =~ m{\A/tmp/\.X11-unix:} } @$entries ),
    'socket directory itself is not unveiled' );
ok( !( grep { $_ eq '/tmp/.X11-unix' } @$entries ),
    'socket directory path absent' );

# Only the exact nested socket is present
my @sockets = grep { m{\.X11-unix} } @$entries;
is_deeply( \@sockets, ["$socket:w"], 'only the exact nested socket' );

# The Xephyr-only authority files must never be unveiled to the app
my $parent_auth = '/var/run/xsunaba/deadbeef/xephyr/parent-auth';
my $server_auth = '/var/run/xsunaba/deadbeef/xephyr/server-auth';
for my $secret ( $parent_auth, $server_auth ) {
    ok( !( grep { $_ =~ /\A\Q$secret\E:/ } @$entries ),
        "Xephyr authority file not unveiled: $secret" );
}

# Empty user configuration still yields the mandatory entries
$entries = Xsunaba::Helper::build_unveil_entries(
    socket_path  => $socket,
    client_auth  => $client_auth,
    runtime_dir  => $runtime,
    user_entries => [],
);
is_deeply( $entries, [ "$socket:w", "$client_auth:r", "$runtime:rwxc" ],
    'mandatory entries without user configuration' );

done_testing;
