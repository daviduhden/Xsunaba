#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/lib";
use TestHelper qw(dies_ok lives_ok);

require "$FindBin::Bin/../libexec/xsunaba-helper";

my ( $FAMILY_LOCAL, $FAMILY_WILD ) =
  ( Xsunaba::Helper::FAMILY_LOCAL(), Xsunaba::Helper::FAMILY_WILD(), );

# --- Record packing and parsing round trip -------------------------
my $cookie = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
my $records =
  Xsunaba::Helper::xauth_records_for( 'test.example.org', '32', $cookie, );

is( scalar @$records,       2,                    'two records generated' );
is( $records->[0]{family},  $FAMILY_LOCAL,        'local family' );
is( $records->[0]{address}, 'test.example.org',   'hostname address' );
is( $records->[0]{number},  '32',                 'display number' );
is( $records->[0]{name},    'MIT-MAGIC-COOKIE-1', 'auth name' );
is( unpack( 'H*', $records->[0]{data} ), $cookie,      'local cookie data' );
is( $records->[1]{family},               $FAMILY_WILD, 'wild family' );
is( $records->[1]{address},              '',           'wild address empty' );

my $bytes  = Xsunaba::Helper::xauth_record_bytes( $records->[0] );
my $parsed = Xsunaba::Helper::parse_xauth_bytes($bytes);
is( scalar @$parsed, 1, 'one record parsed back' );
is_deeply( $parsed->[0], $records->[0], 'record round trip' );

my $all = join '', map { Xsunaba::Helper::xauth_record_bytes($_) } @$records;
$parsed = Xsunaba::Helper::parse_xauth_bytes($all);
is( scalar @$parsed, 2, 'two records parsed back' );
is_deeply( $parsed, $records, 'both records round trip' );

# --- File write / read round trip ----------------------------------
my $dir  = tempdir( CLEANUP => 1 );
my $path = "$dir/auth";
Xsunaba::Helper::write_xauth_file( $path, $records );
my @st = stat $path;
is( $st[2] & 0777, 0600, 'authority file mode 0600' );
my $read = Xsunaba::Helper::read_xauth_file($path);
is_deeply( $read, $records, 'file round trip' );

dies_ok { Xsunaba::Helper::write_xauth_file( $path, $records ) }
qr/exist/i, 'O_EXCL prevents overwrite';

# --- Parent authority extraction -----------------------------------
my $cookie0 = pack( 'H*', '00112233445566778899aabbccddeeff' );
my $cookie1 = pack( 'H*', 'ffeeddccbbaa99887766554433221100' );
my $parent  = [
    {
        family  => $FAMILY_LOCAL,
        address => 'host',
        number  => '0',
        name    => 'MIT-MAGIC-COOKIE-1',
        data    => $cookie0,
    },
    {
        family  => $FAMILY_LOCAL,
        address => 'host',
        number  => '0',
        name    => 'XDM-AUTHORIZATION-1',
        data    => 'x' x 16,
    },
    {
        family  => 0,                      # FamilyInternet
        address => "\x7f\x00\x00\x01",
        number  => '0',
        name    => 'MIT-MAGIC-COOKIE-1',
        data    => $cookie0,
    },
    {
        family  => $FAMILY_LOCAL,
        address => 'host',
        number  => '1',
        name    => 'MIT-MAGIC-COOKIE-1',
        data    => $cookie1,
    },
];

my $parent_bytes = join '',
  map { Xsunaba::Helper::xauth_record_bytes($_) } @$parent;

my $matched =
  Xsunaba::Helper::extract_parent_auth(
    Xsunaba::Helper::parse_xauth_bytes($parent_bytes), ':0', );
is( scalar @$matched, 2, 'only display :0 MIT-MAGIC-COOKIE-1 records' );
for my $m (@$matched) {
    is( $m->{number}, '0',                  'extracted number' );
    is( $m->{name},   'MIT-MAGIC-COOKIE-1', 'extracted name' );
    is(
        unpack( 'H*', $m->{data} ),
        unpack( 'H*', $cookie0 ),
        'extracted cookie'
    );
}

is( Xsunaba::Helper::parent_display_number(':0'),   '0',  'number :0' );
is( Xsunaba::Helper::parent_display_number(':0.1'), '0',  'number :0.1' );
is( Xsunaba::Helper::parent_display_number(':12'),  '12', 'number :12' );

# No MIT-MAGIC-COOKIE-1 for that display => empty (caller fails closed)
my $none = Xsunaba::Helper::extract_parent_auth(
    Xsunaba::Helper::parse_xauth_bytes($parent_bytes), ':9', );
is( scalar @$none, 0, 'no records for unused display' );

# Wrong cookie length must be rejected
my $bad = [
    {
        family  => $FAMILY_LOCAL,
        address => 'host',
        number  => '0',
        name    => 'MIT-MAGIC-COOKIE-1',
        data    => 'short',
    },
];
my $bad_bytes = Xsunaba::Helper::xauth_record_bytes( $bad->[0] );
dies_ok {
    Xsunaba::Helper::extract_parent_auth(
        Xsunaba::Helper::parse_xauth_bytes($bad_bytes), ':0', );
}
qr/length/i, 'short cookie rejected';

# --- Hostile input handling ----------------------------------------
lives_ok { Xsunaba::Helper::parse_xauth_bytes('') } qr//, 'empty file parses';
dies_ok {
    Xsunaba::Helper::parse_xauth_bytes("\x00\x00");
}
qr/truncated/, 'truncated header rejected';
dies_ok {
    Xsunaba::Helper::parse_xauth_bytes( pack( 'n5', 256, 5000, 0, 0, 0 ) );
}
qr/too long/, 'oversized address length rejected';
dies_ok {
    Xsunaba::Helper::parse_xauth_bytes(
        pack( 'n5', 256, 1, 1, 1, 1 ) . "\x00" );
}
qr/truncated/, 'truncated record rejected';
dies_ok {
    Xsunaba::Helper::parse_xauth_bytes(
        Xsunaba::Helper::xauth_record_bytes( $records->[0] ) . 'xx' );
}
qr/truncated/, 'trailing garbage rejected';
dies_ok {
    Xsunaba::Helper::xauth_record_bytes(
        {
            family  => 256,
            address => 'x' x 5000,
            number  => '0',
            name    => 'n',
            data    => ''
        }
    );
}
qr/too long/, 'oversized record packing rejected';

# --- File size limit ------------------------------------------------
my $big = "$dir/big";
open my $bfh, '>', $big or die $!;
print {$bfh} 'x' x ( $Xsunaba::Helper::MAX_XAUTH + 10 );
close $bfh;
dies_ok { Xsunaba::Helper::read_xauth_file($big) }
qr/size limit/, 'oversized authority file rejected';

done_testing;
