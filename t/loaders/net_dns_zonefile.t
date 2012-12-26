use strict;
use warnings;

# test converting records created by Net::DNS::ZoneFile into Stubs

use Test::More;
use Path::Class;

# Net::DNS incorporated ::ZoneFile around 0.70, but ::ZoneFile as an
# independent distribution is at 1.04.  Thus, we need to declare our
# versioned dependency on Net::DNS, not ::ZoneFile.  *le sigh*

use Net::DNS '0.71';
use aliased 'Net::DNS::ZoneFile' => 'ZoneParse';;
use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

my @check = qw{ type ttl name };

my $zp = ZoneParse->new(
    file(qw{ t loaders testzone.db })->stringify,
);

while (my $rr = $zp->read) {

    note ref $rr;
    isa_ok $rr, 'Net::DNS::RR';
    my $stub = Stub->new_from_net_dns_rr(rr => $rr);
    isa_ok $stub, Stub;
    is $rr->type, $stub->type, 'rr/stub types are the same';

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
}

# Net::DNS::ZoneFile's origin() and ttl() methods are only correct _after_
# its read the entire(?) file.
is $zp->origin, 'example.com', 'name is correct';
is $zp->ttl,          '86400', 'ttl is correct';

done_testing;
