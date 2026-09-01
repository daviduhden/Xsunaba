#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

# The helper sets umask 077 before any session/user data is created
# and before the application starts. Verify the resulting defaults
# with the POSIX-permitted subset (mkdir/open) on this platform.
my $dir = tempdir( CLEANUP => 1 );

my $old = umask 077;

mkdir "$dir/private" or die $!;
my @d = stat "$dir/private";
is( ( $d[2] & 0777 ), 0700, 'new directory default 0700' );

open my $fh, '>', "$dir/file" or die $!;
close $fh;
my @f = stat "$dir/file";
is( ( $f[2] & 0777 ), 0600, 'new regular file default 0600' );

umask $old;
done_testing;
