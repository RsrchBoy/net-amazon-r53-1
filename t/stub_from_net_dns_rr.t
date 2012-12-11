use strict;
use warnings;

use autobox::Core;
use Tie::IxHash;

use Test::More;
use Test::Requires 'Net::DNS::RR';
use Test::Requires 'Net::DNS::ZoneFile::Fast';

use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

# debugging...
#use Smart::Comments '###';

# TODO check dies on class ne 'IN'

# most of this test data brazenly stolen from Net-DNS-ZoneFile-Fast-1.17 t/rrs.t

tie my %test, 'Tie::IxHash', (

    q{localhost. 300 IN A 127.0.0.1} => {
        type => 'A',
        ttl  => 300,
        name => 'localhost.',

        resource_records => [ '127.0.0.1' ],
    },

	 #q{localhost IN A 127.0.0.1},
	 #q{localhost A 127.0.0.1},
	 #q{localhost. 300 A 127.0.0.1},
	 q{*.acme.com. 300 IN MX 10 host.acme.com.} => {
        type => 'MX',
        ttl  => 300,
        name => '*.acme.com.',

        resource_records => [ '10 host.acme.com'  ],
     },
	 #q{*           300 IN MX 10 host.acme.com.},
	 #q{10.10.10.10.in-addr.arpa 300 IN PTR www.acme.com.},
	 #q{10.10.10.10.in-addr.arpa. 300 IN PTR www.acme.com.},
	 #q{10.10.10.10.in-addr.arpa. 300 PTR www.acme.com.},
	 #q{10.10.10.10.in-addr.arpa. IN PTR www.acme.com.},
	 #q{10.10.10.10.in-addr.arpa PTR www.acme.com.},

         #q{10.10/10.10.10.in-addr.arpa. IN PTR www.acme.com.},
	 #q{. 3600 IN NS dns1.acme.com.},
	 #q{acme.com. 3600 IN NS dns1.acme.com.},
	 #q{@ 3600 IN NS dns1.acme.com.},
     q{acme.com. 100 IN CNAME www.acme.com.} => {
        type => 'CNAME',
        ttl  => 100,
        name => 'acme.com.',

        resource_records => [ 'www.acme.com.' ],
     },

	 #q{acme.com. 100 IN DNAME example.com.},
	 #q{text.acme.com. 100 IN TXT "This is a quite long text"},
	 #q{text.acme.com IN TXT "This is another piece"},
	 #q{text.acme.com TXT "This is another piece"},
	 #q{text.acme.com. 100 IN SPF "SPF record - contents not checked for SPF validity"},
     q{text.acme.com. IN SPF "SPF record - contents not checked for SPF validity"} => {
         type => 'SPF',
         ttl => 0,
         name => 'text.acme.com.',

         resource_records => [
             '"SPF record - contents not checked for SPF validity"',
         ],
     },
	 #q{* 100 IN MX 10 mailhost.acme.com.},
	 #q{* IN A 1.2.3.4},
	 #q{* 10 IN A 1.2.3.4},
##	 q{* IN 10 A 1.2.3.4},   XXX newer Net::DNS does not like this syntax
	 #q{acme.com. 200 IN MX 10 mailhost.acme.com.},
	 #q{acme.com. 200 IN MX 10 .},
	 #q{acme.com. IN MX 10 mailhost.acme.com.},
	 #q{acme.com. MX 10 mailhost.acme.com.},
	 #q{acme.com. IN SOA dns1.acme.com. me.acme.com. ( 1 2 3 4 5 )},
	 #q{. IN SOA dns1.acme.com. hostmaster.acme.com. ( 1 1 1 1 1 )},
	 #q{@ IN SOA dns1.acme.com. hostmaster.acme.com. ( 1 1 1 1 1 )},
	 #q{. IN SOA dns1.acme.com. hostmaster.acme.com. ( 1 1 1 1 1 )},
         ## included te test cpan bug 17745
	 #q{. IN SOA dns1.acme.com. hostmaster.acme.com ( 1 1 1 1 1 )},
	 #q{. IN SOA dns1.acme.com. hostmaster ( 1 1 1 1 1 )},
	 #q{. IN SOA dns1.acme.com hostmaster.acme.com. ( 1 1 1 1 1 )},
	 #q{. IN SOA dns1 hostmaster. ( 1 1 1 1 1 )},
	 #q{. IN SOA @ hostmaster.acme.com. ( 1 1 1 1 1 )},
	 #q{acme.com. IN AAAA 2001:688:0:102::1:2},
	 #q{acme.com. IN AAAA 2001:688:0:102::3},
	 #q{acme.com. IN RP abuse.acme.com. acme.com.},
	 #q{acme.com. IN SSHFP 2 1 123456789ABCDEF67890123456789ABCDEF67890},
	 #q{acme.com. IN HINFO SUN4/110 UNIX},
	 #q{acme.com. IN HINFO "SUN4/110 foo" UNIX},
	 #q{acme.com. IN HINFO "SUN4/110 foo" "UNIX bar"},
 );

my @check = qw{ type ttl name };
my $i     = 0;

for my $zone_line (keys %test) {

    $i++;

    subtest "[subtest $i] checking $zone_line" => sub {

        my ($rr, $zf_rr);
        my ($rr_stub, $zf_rr_stub);

        my $origin = 'acme.com.';

        subtest '[subtest] checking with Net::DNS::RR->new()' => sub {

            $rr = Net::DNS::RR->new($zone_line);
            ok defined $rr, 'Net::DNS::RR->new($zone_line) returns a value';
            isa_ok $rr, 'Net::DNS::RR';

            my $stub = Stub->new_from_net_dns_rr(rr => $rr);
            isa_ok $stub, Stub;

            is_deeply {
                ( map { $_ => $stub->$_() } @check, 'resource_records' ),
            },
            {
                ( map { $_ => $rr->$_() } @check ),
                resource_records => [ $rr->rdatastr ],
                name             => $rr->name . q{.},
            },
            'stub and Net::DNS::RR appear to match',
            ;

            $rr_stub = $stub;
        };

        subtest '[subtest] checking with Net::DNS::ZoneFile::Fast::parse()' => sub {

            my $zf_rrs = Net::DNS::ZoneFile::Fast::parse(
                text   => "$zone_line",
                origin => '.acme.com.',
            );

            is $zf_rrs->length, 1, '1 rr returned';
            $zf_rr = $zf_rrs->[0];
            isa_ok $zf_rr, 'Net::DNS::RR';

            my $stub = Stub->new_from_net_dns_rr(rr => $zf_rr);
            isa_ok $stub, Stub;

            is_deeply {
                (map { $_ => $stub->$_() } @check, 'resource_records' ),
            },
            {
                (map { $_ => $zf_rr->{$_} } @check ),
                resource_records => [ $zf_rr->rdatastr ],
                name => $rr->name . q{.},
            },
            'stub and Net::DNS::RR (from zone import) appear to match',
            ;

            $zf_rr_stub = $stub;
        };
        
        ok $rr_stub == $zf_rr_stub, 'stubs are equivalent';
    };
}

done_testing;
