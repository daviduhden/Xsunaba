#!/usr/bin/perl

# Tool for sandboxing X11 applications
#
# Uses Xephyr to create a nested X server and runs
# the specified application inside it, with authentication
# cookies managed via xauth.
# Usage:
#   Xsunaba.pl [application and args]
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.

use strict;
use warnings;
use File::Basename;

# Logging
my $no_color  = 0;
my $is_tty    = ( -t STDOUT )             ? 1 : 0;
my $use_color = ( !$no_color && $is_tty ) ? 1 : 0;

my ( $GREEN, $YELLOW, $RED, $CYAN, $BOLD, $RESET ) = ( "", "", "", "", "", "" );
if ($use_color) {
    $GREEN  = "\e[32m";
    $YELLOW = "\e[33m";
    $RED    = "\e[31m";
    $CYAN   = "\e[36m";
    $BOLD   = "\e[1m";
    $RESET  = "\e[0m";
}

sub logi { print "${GREEN}✅ [INFO]${RESET} $_[0]\n"; }
sub logw { print STDERR "${YELLOW}⚠️ [WARN]${RESET} $_[0]\n"; }
sub loge { print STDERR "${RED}❌ [ERROR]${RESET} $_[0]\n"; }

sub die_tool {
    my ($msg) = @_;
    loge($msg);
    exit 1;
}

# Environment variables and default values
my $VERBOSE         = $ENV{VERBOSE}         // 'false';      # Verbose mode
my $XSUNABA_DISPLAY = $ENV{XSUNABA_DISPLAY} // ':32';        # Default display
my $XSUNABA_USER    = $ENV{XSUNABA_USER}    // 'xsunaba';    # Default user
my $HOME            = $ENV{HOME} // die_tool "HOME not found";  # Home directory
my $XSUNABA_XAUTH   = "$HOME/.Xauthority-xsunaba";    # Xauthority file
my $LOCAL_SOCKETS   = "/tmp/.X11-unix";               # Local sockets directory
my $WIDTH           = $ENV{WIDTH}  // 1024;           # Default window width
my $HEIGHT          = $ENV{HEIGHT} // 768;            # Default window height
my $APPLICATION     = join( " ", @ARGV );             # Application to run

# Paths to required binaries
my $OPENSSL = '/usr/bin/openssl';
my $XAUTH   = '/usr/X11R6/bin/xauth';
my $DOAS    = '/usr/bin/doas';
my $XEPHYR  = '/usr/X11R6/bin/Xephyr';

sub setup_sandbox {
    return unless $^O eq 'openbsd';

    eval {
        require OpenBSD::Pledge;
        require OpenBSD::Unveil;

        my @rx_paths = ( $OPENSSL, $XAUTH, $DOAS, $XEPHYR, '/bin/sh' );
        my @r_paths  = ( '/etc', '/dev' );
        my @rwc_paths =
          ( $HOME, "/home/$XSUNABA_USER", '/tmp', $LOCAL_SOCKETS );

        for my $p (@rx_paths) {
            OpenBSD::Unveil::unveil( $p, 'rx' );
        }
        for my $p (@r_paths) {
            OpenBSD::Unveil::unveil( $p, 'r' );
        }
        for my $p (@rwc_paths) {
            OpenBSD::Unveil::unveil( $p, 'rwc' );
        }

        OpenBSD::Unveil::unveil();
        OpenBSD::Pledge::pledge(
            'stdio rpath wpath cpath fattr proc exec inet dns unix')
          or die "pledge failed";
        1;
    } or do {
        logw("OpenBSD pledge/unveil setup failed: $@");
    };
}

# Generate authentication cookie using openssl
my $XSUNABA_MCOOKIE = `$OPENSSL rand -hex 16`;
chomp($XSUNABA_MCOOKIE);

# Global variable for Xephyr's PID
my $XSUNABA_XEPHYR_PID;

# Function: Adjusts the window dimensions based on the application
sub adjust_window_dimensions {
    my $first_arg = shift // "";
    if ( $VERBOSE eq 'true' ) {
        logi(   "Checking for window geometry hacks for '"
              . basename($first_arg)
              . "'..." );
    }
    my $base = basename($first_arg);
    if ( $base eq "chrome" ) {
        $APPLICATION .=
          " -window-size=${WIDTH},${HEIGHT} --window-position=0,0";
    }
    elsif ( $base eq "firefox" ) {
        $APPLICATION .= " -width $WIDTH -height $HEIGHT";
    }
}

# Function: Find an unused X display between :32 and :99
sub find_unused_display {
    for my $i ( 32 .. 99 ) {
        my $sock_file = "$LOCAL_SOCKETS/X$i";
        if ( !-e $sock_file ) {
            $XSUNABA_DISPLAY = ":$i";
            last;
        }
    }
    if ( $VERBOSE eq 'true' ) {
        ( my $display_num = $XSUNABA_DISPLAY ) =~ s/^://;
        logi("Using display $display_num");
    }
}

# Function: Start Xephyr and configure authentication
sub start_xephyr {
    if ( $VERBOSE eq 'true' ) {
        logi("Starting Xephyr on display $XSUNABA_DISPLAY...");
    }
    my $xauth_cmd =
      "$XAUTH -f $XSUNABA_XAUTH add $XSUNABA_DISPLAY . $XSUNABA_MCOOKIE";
    system($xauth_cmd) == 0 or do {
        loge("Failed to add authentication cookie to xauth.");
    };

    my $screen_arg = "${WIDTH}x${HEIGHT}";
    my $xephyr_cmd =
"$XEPHYR -auth $XSUNABA_XAUTH -screen $screen_arg -br -nolisten tcp $XSUNABA_DISPLAY";

    # Run Xephyr in the background using fork
    my $pid = fork();
    if ( !defined $pid ) {
        die_tool "Cannot fork: $!";
    }
    if ( $pid == 0 ) {

        # Child process: replace current process with Xephyr
        exec($xephyr_cmd) or die_tool "Cannot exec Xephyr: $!";
    }
    else {
        # Parent process: store the PID and wait for Xephyr to start
        $XSUNABA_XEPHYR_PID = $pid;
        sleep 3;

        # Verify that the Xephyr process is still running
        if ( kill 0, $XSUNABA_XEPHYR_PID ) {
            print "Xephyr started with PID $XSUNABA_XEPHYR_PID\n"
              if $VERBOSE eq 'true';
        }
        else {
            loge("Failed to start Xephyr. Exiting.");
        }
    }
}

# Function: Launch the application in the sandbox environment (as user XSUNABA_USER)
sub launch_application {
    if ( $VERBOSE eq 'true' ) {
        logi("Launching '$APPLICATION' on display $XSUNABA_DISPLAY...");
    }

    # Create the .Xauthority file if it doesn't exist
    my $touch_cmd =
      "$DOAS -u $XSUNABA_USER touch /home/$XSUNABA_USER/.Xauthority";
    system($touch_cmd) == 0 or do {
        loge("Failed to touch .Xauthority for $XSUNABA_USER.");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
    };

    # Add the authentication cookie for the sandbox user
    my $xauth_add_cmd =
      "$DOAS -u $XSUNABA_USER $XAUTH add $XSUNABA_DISPLAY . $XSUNABA_MCOOKIE";
    system($xauth_add_cmd) == 0 or do {
        logw("Failed to add authentication cookie for $XSUNABA_USER.");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        system("$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY");
        exit 1;
    };

    # Launch the application with the DISPLAY variable set
    my $app_cmd =
      "$DOAS -u $XSUNABA_USER env DISPLAY=$XSUNABA_DISPLAY $APPLICATION";
    system($app_cmd) == 0 or do {
        logw("Failed to run the application as $XSUNABA_USER");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        system("$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY");
        system("$DOAS -u $XSUNABA_USER $XAUTH remove $XSUNABA_DISPLAY");
        exit 1;
    };

    logi("Application '$APPLICATION' launched successfully")
      if $VERBOSE eq 'true';
}

# Function: Stop Xephyr
sub stop_xephyr {
    if ( $VERBOSE eq 'true' ) {
        logi("Stopping Xephyr with PID $XSUNABA_XEPHYR_PID...");
    }
    if ( kill 0, $XSUNABA_XEPHYR_PID ) {
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        sleep 1;
        if ( kill 0, $XSUNABA_XEPHYR_PID ) {
            loge("Failed to stop Xephyr. Exiting.");
        }
    }
    logi("Xephyr stopped successfully") if $VERBOSE eq 'true';
}

# Function: Remove the authentication cookie
sub clear_authentication_cookie {
    if ( $VERBOSE eq 'true' ) {
        logi("Clearing authentication cookie for display $XSUNABA_DISPLAY...");
    }
    my $remove_cmd = "$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY";
    system($remove_cmd) == 0 or do {
        loge("Failed to remove authentication cookie from xauth.");
    };
    my $remove_cmd2 = "$DOAS -u $XSUNABA_USER $XAUTH remove $XSUNABA_DISPLAY";
    system($remove_cmd2) == 0 or do {
        logw("Failed to remove authentication cookie for $XSUNABA_USER.");
        exit 1;
    };
    logi("Authentication cookie cleared") if $VERBOSE eq 'true';
}

# Main script execution
sub main {
    setup_sandbox();
    if (@ARGV) {
        adjust_window_dimensions( $ARGV[0] );
    }
    else {
        loge("No application specified. Exiting.");
    }

    find_unused_display();
    start_xephyr();
    launch_application();
    stop_xephyr();
    clear_authentication_cookie();
}

main();
