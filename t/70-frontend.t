#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
no warnings qw(once);
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use FindBin;

require "$FindBin::Bin/../bin/Xsunaba.pl";

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
        '--verbose',
        '--',
        '/usr/bin/xterm', '-e', 'true',
    ],
    'helper argv exact',
);

@argv = Xsunaba::build_helper_argv(
    parent_display => ':0',
    parent_xauth   => '/home/u/.Xauthority',
    app_argv       => [ '/bin/true' ],
);
is_deeply(
    \@argv,
    [ '--parent-display', ':0', '--parent-xauth', '/home/u/.Xauthority',
      '--', '/bin/true' ],
    'minimal helper argv',
);

# --- Frontend validation and end-to-end argv -----------------------
# CLEANUP disabled: the forked children inherit the tempdir object and
# must not delete it on their own exit.
my $dir = tempdir( CLEANUP => 0 );
my $xauth = "$dir/xauth";
open my $fh, '>', $xauth or die $!;
print {$fh} "placeholder";
close $fh;

my %base_env = %ENV;

{
    local %ENV = %base_env;
    delete @ENV{qw(DISPLAY XAUTHORITY XSUNABA_PLEDGE
        XSUNABA_UNVEIL XSUNABA_DISPLAY WIDTH HEIGHT VERBOSE
        XSUNABA_VERBOSE)};
    $ENV{HOME} = $dir;
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/DISPLAY not set/ms, 'no DISPLAY is rejected' );
}

{
    local %ENV = %base_env;
    delete @ENV{qw(DISPLAY XAUTHORITY HOME XSUNABA_PLEDGE
        XSUNABA_UNVEIL XSUNABA_DISPLAY WIDTH HEIGHT VERBOSE
        XSUNABA_VERBOSE)};
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/HOME not set/ms, 'no HOME is rejected' );
}

{
    local %ENV = %base_env;
    delete @ENV{qw(XSUNABA_PLEDGE XSUNABA_UNVEIL XSUNABA_DISPLAY
        WIDTH HEIGHT VERBOSE XSUNABA_VERBOSE)};
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = $xauth;

    my $fake = "$dir/fake-doas";
    my $out  = "$dir/doas-argv";
    open my $s, '>', $fake or die $!;
    my $perl = $^X;
    print {$s} "#!$perl\n";
    print {$s} <<'FAKE';
#!/usr/bin/perl
use strict;
use warnings;
open my $fh, '>', $ENV{FAKE_DOAS_OUT} or die $!;
print {$fh} join("\0", @ARGV), "\0";
close $fh;
FAKE
    close $s;
    chmod 0755, $fake or die $!;
    local $Xsunaba::DOAS_BIN = $fake;

    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( $pid == 0 ) {
        $ENV{FAKE_DOAS_OUT} = $out;
        $ENV{VERBOSE}       = 1;
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
    my $raw = do { local $/; <$rf> };
    close $rf;
    my @got = split /\0/, $raw, -1;
    pop @got;    # trailing empty
    is_deeply(
        \@got,
        [
            $Xsunaba::HELPER,
            '--parent-display', ':0',
            '--parent-xauth',   $xauth,
            '--display',        '40',
            '--width',          '1280',
            '--height',         '900',
            '--unveil',         '/tmp:rwc,/etc:r',
            '--verbose',
            '--',
            '/usr/bin/xterm', '-e', 'true',
        ],
        'end-to-end argv through doas',
    );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = $xauth;
    $ENV{XSUNABA_PLEDGE} = 'stdio';
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/execpromises/, 'non-empty XSUNABA_PLEDGE rejected' );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = 'hostname:0';
    $ENV{XAUTHORITY} = $xauth;
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/Invalid DISPLAY/, 'remote parent display rejected' );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = "$dir/nonexistent";
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/Cannot read Xauthority/, 'missing Xauthority rejected' );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = $xauth;
    $ENV{XSUNABA_DISPLAY} = ':abc';
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/Invalid display/, 'invalid nested display rejected' );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = $xauth;
    $ENV{WIDTH} = '99999999';
    eval { Xsunaba::launch( app => '/bin/true' ) };
    like( $@, qr/width/, 'oversized width rejected' );
}

{
    local %ENV = %base_env;
    $ENV{HOME}    = $dir;
    $ENV{DISPLAY} = ':0';
    $ENV{XAUTHORITY} = $xauth;
    eval { Xsunaba::launch( app => '/usr/bin/xterm', display => ':50',
        width => 1000, height => 800 ) };
    like( $@, qr/exec \/usr\/bin\/doas/, 'real doas missing on Linux' );
}

remove_tree($dir);
done_testing;
