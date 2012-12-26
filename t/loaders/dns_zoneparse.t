use strict;
use warnings;

use Test::More
    skip_all => 'DNS::ZoneParse known to not handle SPF records';

use Path::Class;
use Test::Requires 'DNS::ZoneParse';

use constant ZoneParse => 'DNS::ZoneParse';

# fail looks like:
# [
#   bless( [], 'DNS::ZoneParse' ),
#   '@ 0 IN SPF "v=spf1 +mx a:colo.example.com/28 -all"',
#   'Unknown record type',
#   'tess CNAME dne.other.com.'
# ]

my $zp = DNS::ZoneParse->new(
    file(qw{ t loaders testzone.db })->stringify,
    undef,
    sub {
        fail;
        note explain \@_;
    },
);

my $dump = $zp->dump;

note explain $dump;

done_testing;
