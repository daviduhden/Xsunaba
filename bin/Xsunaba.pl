#!/usr/bin/perl

# Xsunaba - Tool for sandboxing X11 applications
#
# Originally based on http://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/

# MIT License
#
# Copyright (c) 2013 Milosz Galazka
# Copyright (c) 2020 Morgan Aldridge
# Copyright (c) 2025 David Uhden Collado
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

use strict;
use warnings;
use File::Basename;

my $GREEN = "\e[32m";
my $YELLOW = "\e[33m";
my $RED = "\e[31m";
my $CYAN = "\e[36m";
my $BOLD = "\e[1m";
my $RESET = "\e[0m";

sub log {
    my ($msg) = @_;
    print "${GREEN}✅ [INFO]${RESET} $msg\n";
}

sub warn {
    my ($msg) = @_;
    print STDERR "${YELLOW}⚠️  [WARN]${RESET} $msg\n";
}

sub error {
    my ($msg, $code) = @_;
    $code //= 1;
    print STDERR "${RED}❌ [ERROR]${RESET} $msg\n";
    exit $code;
}

# Backward-compatible aliases
sub info     { log(@_); }
sub warn_msg { warn(@_); }

# Environment variables and default values
my $VERBOSE         = $ENV{VERBOSE}         // 'false';  # Verbose mode
my $XSUNABA_DISPLAY = $ENV{XSUNABA_DISPLAY} // ':32';    # Default display
my $XSUNABA_USER    = $ENV{XSUNABA_USER}    // 'xsunaba';# Default user
my $HOME            = $ENV{HOME}            // die "HOME not found"; # Home directory
my $XSUNABA_XAUTH   = "$HOME/.Xauthority-xsunaba"; # Xauthority file
my $LOCAL_SOCKETS   = "/tmp/.X11-unix";     # Local sockets directory
my $WIDTH           = $ENV{WIDTH}  // 1024; # Default window width
my $HEIGHT          = $ENV{HEIGHT} // 768;  # Default window height
my $APPLICATION     = join(" ", @ARGV);     # Application to run

# Paths to required binaries
my $OPENSSL = '/usr/bin/openssl';
my $XAUTH = '/usr/X11R6/bin/xauth';
my $DOAS = '/usr/bin/doas';
my $XEPHYR = '/usr/X11R6/bin/Xephyr';

# Generate authentication cookie using openssl
my $XSUNABA_MCOOKIE = `$OPENSSL rand -hex 16`;
chomp($XSUNABA_MCOOKIE);

# Global variable for Xephyr's PID
my $XSUNABA_XEPHYR_PID;

# Function: Adjusts the window dimensions based on the application
sub adjust_window_dimensions {
    my $first_arg = shift // "";
    if ($VERBOSE eq 'true') {
        log("Checking for window geometry hacks for '" . basename($first_arg) . "'...");
    }
    my $base = basename($first_arg);
    if ($base eq "chrome") {
        $APPLICATION .= " -window-size=${WIDTH},${HEIGHT} --window-position=0,0";
    } elsif ($base eq "firefox") {
        $APPLICATION .= " -width $WIDTH -height $HEIGHT";
    }
}

# Function: Find an unused X display between :32 and :99
sub find_unused_display {
    for my $i (32 .. 99) {
        my $sock_file = "$LOCAL_SOCKETS/X$i";
        if ( ! -e $sock_file ) {
            $XSUNABA_DISPLAY = ":$i";
            last;
        }
    }
    if ($VERBOSE eq 'true') {
        (my $display_num = $XSUNABA_DISPLAY) =~ s/^://;
        log("Using display $display_num");
    }
}

# Function: Start Xephyr and configure authentication
sub start_xephyr {
    if ($VERBOSE eq 'true') {
        log("Starting Xephyr on display $XSUNABA_DISPLAY...");
    }
    my $xauth_cmd = "$XAUTH -f $XSUNABA_XAUTH add $XSUNABA_DISPLAY . $XSUNABA_MCOOKIE";
    system($xauth_cmd) == 0 or do {
        error("Failed to add authentication cookie to xauth.");
    };

    my $screen_arg = "${WIDTH}x${HEIGHT}";
    my $xephyr_cmd = "$XEPHYR -auth $XSUNABA_XAUTH -screen $screen_arg -br -nolisten tcp $XSUNABA_DISPLAY";

    # Run Xephyr in the background using fork
    my $pid = fork();
    if ( !defined $pid ) {
        die "Cannot fork: $!";
    } 
    if ( $pid == 0 ) {
        # Child process: replace current process with Xephyr
        exec($xephyr_cmd) or die "Cannot exec Xephyr: $!";
    } else {
        # Parent process: store the PID and wait for Xephyr to start
        $XSUNABA_XEPHYR_PID = $pid;
        sleep 3;
        # Verify that the Xephyr process is still running
        if ( kill 0, $XSUNABA_XEPHYR_PID ) {
            print "Xephyr started with PID $XSUNABA_XEPHYR_PID\n" if $VERBOSE eq 'true';
        } else {
            error("Failed to start Xephyr. Exiting.");
        }
    }
}

# Function: Launch the application in the sandbox environment (as user XSUNABA_USER)
sub launch_application {
    if ($VERBOSE eq 'true') {
        log("Launching '$APPLICATION' on display $XSUNABA_DISPLAY...");
    }
    # Create the .Xauthority file if it doesn't exist
    my $touch_cmd = "$DOAS -u $XSUNABA_USER touch /home/$XSUNABA_USER/.Xauthority";
    system($touch_cmd) == 0 or do {
        error("Failed to touch .Xauthority for $XSUNABA_USER.");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
    };

    # Add the authentication cookie for the sandbox user
    my $xauth_add_cmd = "$DOAS -u $XSUNABA_USER $XAUTH add $XSUNABA_DISPLAY . $XSUNABA_MCOOKIE";
    system($xauth_add_cmd) == 0 or do {
        warn("Failed to add authentication cookie for $XSUNABA_USER.");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        system("$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY");
        exit 1;
    };

    # Launch the application with the DISPLAY variable set
    my $app_cmd = "$DOAS -u $XSUNABA_USER env DISPLAY=$XSUNABA_DISPLAY $APPLICATION";
    system($app_cmd) == 0 or do {
        warn("Failed to run the application as $XSUNABA_USER");
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        system("$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY");
        system("$DOAS -u $XSUNABA_USER $XAUTH remove $XSUNABA_DISPLAY");
        exit 1;
    };

    log("Application '$APPLICATION' launched successfully") if $VERBOSE eq 'true';
}

# Function: Stop Xephyr
sub stop_xephyr {
    if ($VERBOSE eq 'true') {
        log("Stopping Xephyr with PID $XSUNABA_XEPHYR_PID...");
    }
    if ( kill 0, $XSUNABA_XEPHYR_PID ) {
        kill 'TERM', $XSUNABA_XEPHYR_PID;
        sleep 1;
        if ( kill 0, $XSUNABA_XEPHYR_PID ) {
            error("Failed to stop Xephyr. Exiting.");
        }
    }
    log("Xephyr stopped successfully") if $VERBOSE eq 'true';
}

# Function: Remove the authentication cookie
sub clear_authentication_cookie {
    if ($VERBOSE eq 'true') {
        log("Clearing authentication cookie for display $XSUNABA_DISPLAY...");
    }
    my $remove_cmd = "$XAUTH -f $XSUNABA_XAUTH remove $XSUNABA_DISPLAY";
    system($remove_cmd) == 0 or do {
        error("Failed to remove authentication cookie from xauth.");
    };
    my $remove_cmd2 = "$DOAS -u $XSUNABA_USER $XAUTH remove $XSUNABA_DISPLAY";
    system($remove_cmd2) == 0 or do {
        warn("Failed to remove authentication cookie for $XSUNABA_USER.");
        exit 1;
    };
    log("Authentication cookie cleared") if $VERBOSE eq 'true';
}

# Main script execution
sub main {
    if (@ARGV) {
        adjust_window_dimensions($ARGV[0]);
    } else {
        error("No application specified. Exiting.");
    }

    find_unused_display();
    start_xephyr();
    launch_application();
    stop_xephyr();
    clear_authentication_cookie();
}

main();
