package TestHelper;

use strict;
use warnings;
use Exporter   qw(import);
use IPC::Open3 qw(open3);
use Symbol     qw(gensym);
use Test::More;

our @EXPORT_OK = qw(dies_ok lives_ok run_capture);

# Run a command without a shell and capture stdout, stderr and status.
# Run a command with list-form open3, so no shell parses the arguments, and
# collect stdout, stderr and the raw wait status.  The caller decodes $? when it
# cares about exit versus signal status.  The temporary handles are closed and
# the child is reaped before returning.
sub run_capture {
    my (@cmd)      = @_;
    my $err_fh     = gensym();
    my $pid        = open3( my $in, my $out_fh, $err_fh, @cmd );
    my $closed_in  = close $in;
    my $out        = do { local $/ = undef; <$out_fh> };
    my $err        = do { local $/ = undef; <$err_fh> };
    my $closed_out = close $out_fh;
    my $closed_err = close $err_fh;
    waitpid( $pid, 0 );
    return ( defined $out ? $out : '', defined $err ? $err : '', $? );
}

## no critic (Subroutines::ProhibitSubroutinePrototypes)
# The prototypes are the documented Test::More-style call interface.
# Test::More-compatible assertion that a block dies.  An optional regular
# expression is matched against the error after the basic assertion is
# recorded, so a mismatch produces a separate, diagnosable test result.
sub dies_ok (&;@) {
    my ( $code, @rest ) = @_;
    my $re   = @rest ? shift @rest : undef;
    my $name = @rest ? shift @rest : 'code dies as expected';
    my $ok   = !eval { $code->(); 1 };
    my $err  = $@ || '';
    ok( $ok, $name );
    like( $err, $re, "$name: error matches" ) if $re;
    return $err;
}

## no critic (Subroutines::ProhibitSubroutinePrototypes)
# Test::More-compatible assertion that a block completes without dying.  The
# optional regular expression is checked only when the block died; this mirrors
# the helper's documented behavior and avoids asserting against an empty error.
sub lives_ok (&;@) {
    my ( $code, @rest ) = @_;
    my $re   = @rest ? shift @rest : undef;
    my $name = @rest ? shift @rest : 'code lives as expected';
    my $ok   = eval { $code->(); 1 };
    my $err  = $@ || '';
    ok( $ok, $name ) or diag($err);
    like( $err, $re, "$name: error matches" ) if $re && !$ok;
    return $ok;
}

1;
