#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(run_capture);

my ( $stdout, $stderr, $status ) = run_capture(
    'python3', "$FindBin::Bin/../scripts/validate-agent-knowledge.py",
    '--scope', 'worktree'
);
is( $status, 0, 'agent maintenance validator passes for this change set' )
  or diag("stdout: $stdout\nstderr: $stderr");
like(
    $stdout,
    qr/Agent Knowledge Validation/,
    'validator reports its contract summary'
);
like(
    $stdout,
    qr/automation cannot prove semantic correctness/,
    'validator explains semantic review limitation'
);

done_testing;
