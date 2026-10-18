#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use FindBin;

## no critic (Modules::RequireBarewordIncludes)
# The frontend is a script, not a module; it must be loaded by path.
require "$FindBin::Bin/../bin/Xsunaba.pl";

sub write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>', $path or die $!;
    print {$fh} $content or die $!;
    close $fh            or die $!;
    return;
}

# --- Command resolution --------------------------------------------
# The helper requires an absolute program path, but the CLI accepts a
# bare command name; launch() resolves it through PATH.
{
    my $dir = tempdir( CLEANUP => 1 );
    my $exe = "$dir/mytool";
    open my $fh, '>', $exe or die $!;
    close $fh or die $!;
    chmod 0755, $exe or die $!;

    is( Xsunaba::resolve_app( 'mytool', $dir ),
        $exe, 'bare name resolved through the given PATH' );
    is( Xsunaba::resolve_app('/usr/bin/xterm'),
        '/usr/bin/xterm', 'absolute path left unchanged' );
    is( Xsunaba::resolve_app( './local', $dir ),
        './local', 'name containing a slash left unchanged' );
    ok( !defined Xsunaba::resolve_app( 'no-such-tool-xyz', $dir ),
        'unknown command is undefined' );
    ok( !defined Xsunaba::resolve_app( 'mytool', 'bin' ),
        'relative PATH entries are ignored' );
}

# --- Helper argv construction --------------------------------------
my @argv = Xsunaba::build_helper_argv(
    parent_display => ':0',
    parent_xauth   => '/home/u/.Xauthority',
    display        => 40,
    width          => 1280,
    height         => 900,
    unveil         => '/tmp:rwc,/etc:r',
    verbose        => 1,
    app_argv       => [ '/usr/bin/xterm', '-e', 'true' ],
);
is_deeply(
    \@argv,
    [
        '--parent-display', ':0',
        '--parent-xauth',   '/home/u/.Xauthority',
        '--display',        '40',
        '--width',          '1280',
        '--height',         '900',
        '--unveil',         '/tmp:rwc,/etc:r',
        '--verbose',        '--',
        '/usr/bin/xterm',   '-e',
        'true',
    ],
    'helper argv exact',
);

@argv = Xsunaba::build_helper_argv(
    parent_display => ':0',
    parent_xauth   => '/home/u/.Xauthority',
    app_argv       => ['/bin/true'],
);
is_deeply(
    \@argv,
    [
        '--parent-display', ':0',
        '--parent-xauth',   '/home/u/.Xauthority',
        '--',               '/bin/true'
    ],
    'minimal helper argv',
);

@argv = Xsunaba::build_helper_argv(
    parent_display => ':0',
    parent_xauth   => '/home/u/.Xauthority',
    amnesiac       => 1,
    app_argv       => ['/bin/true'],
);
is_deeply(
    \@argv,
    [
        '--parent-display', ':0',
        '--parent-xauth',   '/home/u/.Xauthority',
        '--amnesiac',       '--',
        '/bin/true'
    ],
    'amnesiac flag passed before --',
);

# --- Frontend validation and end-to-end argv -----------------------
# CLEANUP disabled: the forked children inherit the tempdir object and
# must not delete it on their own exit.
my $dir   = tempdir( CLEANUP => 0 );
my $xauth = "$dir/xauth";
write_file( $xauth, 'placeholder' );

my %base_env = %ENV;

# Build a deterministic environment for each launch case. Variables the
# frontend must never inherit are removed unless the case sets them.
sub test_env {
    my (@overrides) = @_;
    my %env = %base_env;
    delete @env{
        qw(DISPLAY XAUTHORITY HOME XSUNABA_PLEDGE XSUNABA_UNVEIL
          XSUNABA_DISPLAY WIDTH HEIGHT VERBOSE XSUNABA_VERBOSE)
    };
    while (@overrides) {
        my ( $key, $value ) = splice @overrides, 0, 2;
        $env{$key} = $value if defined $value;
    }
    return %env;
}

{
    local %ENV = test_env( HOME => $dir );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails without DISPLAY' );
    like( $@, qr/DISPLAY not set/ms, 'no DISPLAY is rejected' );
}

{
    local %ENV = test_env();
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails without HOME' );
    like( $@, qr/HOME not set/ms, 'no HOME is rejected' );
}

{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => $xauth,
    );

    my $fake     = "$dir/fake-doas";
    my $out      = "$dir/doas-argv";
    my $perl     = $^X;
    my $fake_src = "#!$perl\n" . <<'FAKE';
#!/usr/bin/perl
use strict;
use warnings;
open my $fh, '>', $ENV{FAKE_DOAS_OUT} or die $!;
print {$fh} join("\0", @ARGV), "\0";
close $fh;
FAKE
    write_file( $fake, $fake_src );
    chmod 0755, $fake or die $!;
    local $Xsunaba::DOAS_BIN = $fake;

    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( $pid == 0 ) {
        local %ENV = ( %ENV, FAKE_DOAS_OUT => $out, VERBOSE => 1 );
        Xsunaba::launch(
            app     => '/usr/bin/xterm',
            args    => [ '-e', 'true' ],
            display => ':40',
            width   => 1280,
            height  => 900,
            unveil  => [ '/tmp:rwc', '/etc:r' ],
        );
        exit 0;
    }
    waitpid( $pid, 0 );
    is( $? >> 8, 0, 'launch execs the helper cleanly' );
    open my $rf, '<', $out or die $!;
    my $raw = do { local $/ = undef; <$rf> };
    close $rf or die $!;
    my @got = split /\0/, $raw, -1;
    pop @got;    # trailing empty
    is_deeply(
        \@got,
        [
            $Xsunaba::HELPER,  '--parent-display',
            ':0',              '--parent-xauth',
            $xauth,            '--display',
            '40',              '--width',
            '1280',            '--height',
            '900',             '--unveil',
            '/tmp:rwc,/etc:r', '--verbose',
            '--',              '/usr/bin/xterm',
            '-e',              'true',
        ],
        'end-to-end argv through doas',
    );
}

# A bare command name must be resolved through PATH before reaching the
# helper, which requires an absolute application path.
{
    my $bin = "$dir/bin";
    mkdir $bin or die $!;
    my $tool = "$bin/mytool";
    write_file( $tool, '' );
    chmod 0755, $tool or die $!;

    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => $xauth,
        PATH       => $bin,
    );

    my $fake     = "$dir/fake-doas-resolve";
    my $out      = "$dir/doas-argv-resolve";
    my $perl     = $^X;
    my $fake_src = "#!$perl\n" . <<'FAKE';
#!/usr/bin/perl
use strict;
use warnings;
open my $fh, '>', $ENV{FAKE_DOAS_OUT} or die $!;
print {$fh} join("\0", @ARGV), "\0";
close $fh;
FAKE
    write_file( $fake, $fake_src );
    chmod 0755, $fake or die $!;
    local $Xsunaba::DOAS_BIN = $fake;

    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( $pid == 0 ) {
        local %ENV = ( %ENV, FAKE_DOAS_OUT => $out );
        Xsunaba::launch( app => 'mytool', args => ['--flag'] );
        exit 0;
    }
    waitpid( $pid, 0 );
    is( $? >> 8, 0, 'bare command launch execs the helper cleanly' );
    open my $rf, '<', $out or die $!;
    my $raw = do { local $/ = undef; <$rf> };
    close $rf or die $!;
    my @got = split /\0/, $raw, -1;
    pop @got;
    is_deeply(
        \@got,
        [
            $Xsunaba::HELPER, '--parent-display',
            ':0',             '--parent-xauth',
            $xauth,           '--display',
            '32',             '--width',
            '1024',           '--height',
            '768',            '--',
            $tool,            '--flag',
        ],
        'bare name resolved to an absolute path for the helper',
    );
}

{
    local %ENV = test_env(
        HOME           => $dir,
        DISPLAY        => ':0',
        XAUTHORITY     => $xauth,
        XSUNABA_PLEDGE => 'stdio',
    );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails with XSUNABA_PLEDGE' );
    like( $@, qr/execpromises/, 'non-empty XSUNABA_PLEDGE rejected' );
}

{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => 'hostname:0',
        XAUTHORITY => $xauth,
    );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails for a remote parent display' );
    like( $@, qr/Invalid DISPLAY/, 'remote parent display rejected' );
}

{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => "$dir/nonexistent",
    );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails without Xauthority' );
    like( $@, qr/Cannot read Xauthority/, 'missing Xauthority rejected' );
}

{
    local %ENV = test_env(
        HOME            => $dir,
        DISPLAY         => ':0',
        XAUTHORITY      => $xauth,
        XSUNABA_DISPLAY => ':abc',
    );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails for an invalid nested display' );
    like( $@, qr/Invalid display/, 'invalid nested display rejected' );
}

{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => $xauth,
        WIDTH      => '99999999',
    );
    my $ok = eval { Xsunaba::launch( app => '/bin/true' ); 1 };
    ok( !$ok, 'launch fails for an oversized width' );
    like( $@, qr/width/, 'oversized width rejected' );
}

{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => $xauth,
    );

    # Point at a doas that does not exist so the failure is deterministic
    # on every platform. Using the real $DOAS_BIN would exec it on
    # OpenBSD (where doas is installed) and replace the test process.
    local $Xsunaba::DOAS_BIN = "$dir/no-such-dir/doas";
    my $ok = eval {
        Xsunaba::launch(
            app     => '/usr/bin/xterm',
            display => ':50',
            width   => 1000,
            height  => 800
        );
        1;
    };
    ok( !$ok, 'launch fails for a missing doas' );
    like(
        $@,
        qr/exec .*doas/,
        'a non-executable doas fails with a clear message'
    );
}

# --- Amnesiac end-to-end argv and browser-geometry neutrality -------
{
    local %ENV = test_env(
        HOME       => $dir,
        DISPLAY    => ':0',
        XAUTHORITY => $xauth,
    );

    my $fake     = "$dir/fake-doas-amnesiac";
    my $out      = "$dir/doas-argv-amnesiac";
    my $perl     = $^X;
    my $fake_src = "#!$perl\n" . <<'FAKE';
#!/usr/bin/perl
use strict;
use warnings;
open my $fh, '>', $ENV{FAKE_DOAS_OUT} or die $!;
print {$fh} join("\0", @ARGV), "\0";
close $fh;
FAKE
    write_file( $fake, $fake_src );
    chmod 0755, $fake or die $!;
    local $Xsunaba::DOAS_BIN = $fake;

    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( $pid == 0 ) {
        local %ENV = ( %ENV, FAKE_DOAS_OUT => $out );
        Xsunaba::launch(
            amnesiac => 1,
            app      => '/usr/local/bin/firefox',
            args     => ['--private-window'],
            width    => 1100,
            height   => 700,
        );
        exit 0;
    }
    waitpid( $pid, 0 );
    is( $? >> 8, 0, 'amnesiac launch execs cleanly' );
    open my $rf, '<', $out or die $!;
    my $raw = do { local $/ = undef; <$rf> };
    close $rf or die $!;
    my @got = split /\0/, $raw, -1;
    pop @got;
    is_deeply(
        \@got,
        [
            $Xsunaba::HELPER, '--parent-display',
            ':0',             '--parent-xauth',
            $xauth,           '--display',
            '32',             '--width',
            '1100',           '--height',
            '700',            '--amnesiac',
            '--',             '/usr/local/bin/firefox',
            '--private-window',
        ],
        'amnesiac argv exact; no browser geometry hacks appended',
    );
}

remove_tree($dir);
done_testing;
