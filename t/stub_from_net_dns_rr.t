use strict;
use warnings;

# check a number of conversions; not a full batch

use utf8;

use autobox::Core;
use Tie::IxHash;

use Test::More;
use Test::Requires { 'Net::DNS::RR' => '0.71' };
use Test::Requires 'DNS::ZoneParse';
use Test::Requires 'Net::DNS::ZoneFile';

use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

# most of this test data brazenly stolen from Net-DNS-ZoneFile-Fast-1.17 t/rrs.t

tie my %test, 'Tie::IxHash', (

    q{localhost. 300 IN A 127.0.0.1} => {
        type             => 'A',
        ttl              => 300,
        name             => 'localhost.',
        resource_records => [ '127.0.0.1' ],
    },

    q{*.acme.com. 300 IN MX 10 host.acme.com.} => {
        type             => 'MX',
        ttl              => 300,
        name             => '*.acme.com.',
        resource_records => [ '10 host.acme.com'  ],
    },

    q{acme.com. 100 IN CNAME www.acme.com.} => {
        type             => 'CNAME',
        ttl              => 100,
        name             => 'acme.com.',
        resource_records => [ 'www.acme.com.' ],
    },

    q{text.acme.com. 100 IN TXT "This is a quite long text"} => {
        type             => 'TXT',
        ttl              => 100,
        name             => 'acme.com.',
        resource_records => [ '"This is a quite long text"' ],
    },

    q{text.acme.com TXT "This is another piece"} => {
        type             => 'TXT',
        ttl              => 0,
        name             => 'text.acme.com.acme.com.',
        resource_records => [ '"This is a quite long text"' ],
    },

    q{text.acme.com. IN SPF "SPF record - contents not checked for SPF validity"} => {
        type             => 'SPF',
        ttl              => 0,
        name             => 'text.acme.com.',
        resource_records => [ '"SPF record - contents not checked for SPF validity"' ],
    },

    q{acme.com. MX 10 mailhost.acme.com.} => {
        type             => 'MX',
        ttl              => 0,
        name             => 'acme.com.',
        resource_records => [ '10 mailhost.acme.com.' ],
    },

    q{acme.com. IN AAAA 2001:688:0:102::1:2} => {
        type             => 'AAAA',
        ttl              => 0,
        name             => 'acme.com.',
        resource_records => [ '2001:688:0:102::1:2' ],
    },
 );

my @check = qw{ type ttl name };
my $i     = 0;

pass q{Alright! Let's get going, then.};

for my $zone_line (keys %test) {

    $i++;

    subtest "[subtest $i] checking {$zone_line}" => sub {

        my ($rr_stub);
        my $origin = 'acme.com.';

        note "---$zone_line---";
        my $rr = Net::DNS::RR->new($zone_line);
        ok defined $rr, 'Net::DNS::RR->new($zone_line) returns a value';
        isa_ok $rr, 'Net::DNS::RR';

        subtest '[subtest] checking with Net::DNS::RR->new()' => sub {

            # generate a stub, give it an origin
            #my $stub = Stub->new_from_net_dns_rr(rr => $rr, origin => $origin);
            my $stub = Stub->new_from_net_dns_rr(rr => $rr);
            isa_ok $stub, Stub;

            is_deeply(
                { ( map { $_ => $stub->$_() } @check, 'resource_records' ) },
                {
                    ( map { $_ => $rr->$_() } @check ),
                    resource_records => [ $rr->rdatastr ],
                    name             => $rr->name . q{.},
                },
                'stub and Net::DNS::RR appear to match',
            );

            $rr_stub = $stub;
        };

        subtest '[subtest] checking with Net::DNS::ZoneFile::Fast::parse()' => sub {
            return plan skip_all => 'Net::DNS::RRS >= 0.70 has broken Net::DNS::ZoneFile::Fast';
        };

        subtest '[subtest] checking with Net::DNS::ZoneFile::parse()' => sub {

            my $zf_rrs = Net::DNS::ZoneFile->parse(
                #\"\$ORIGIN $origin\n$zone_line",
                $zone_line,
            );

            is $zf_rrs->length, 1, '1 rr returned';
            my $zf_rr = $zf_rrs->[0];
            isa_ok $zf_rr, 'Net::DNS::RR';

            my $stub = Stub->new_from_net_dns_rr(rr => $zf_rr);
            isa_ok $stub, Stub;

            is_deeply {
                (map { $_ => $stub->$_() } @check, 'resource_records' ),
            },
            {
                (map { $_ => $zf_rr->$_() } @check ),
                resource_records => [ $zf_rr->rdatastr ],
                resource_records => [ $zf_rr->rdatastr ],
                name => $rr->name . q{.},
            },
            'stub and Net::DNS::RR (from zone import) appear to match',
            ;

            ok $rr_stub == $stub, 'stubs are equivalent';
        };

    };
}

done_testing;
