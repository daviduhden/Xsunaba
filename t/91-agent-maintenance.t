#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(run_capture);

my ( $stdout, $stderr, $status ) = run_capture(
    'python3', "$FindBin::Bin/../tools/check_agent_maintenance.py", '--worktree'
);
is( $status, 0, 'agent maintenance validator passes for this change set' )
  or diag("stdout: $stdout\nstderr: $stderr");
like( $stdout, qr/Structural checks passed/, 'validator reports structural checks' );
like( $stdout, qr/semantic relevance still requires review/,
    'validator explains semantic review limitation' );

done_testing;
