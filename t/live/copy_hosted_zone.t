use strict;
use warnings;

# test that copying zones works as expected.

use Test::More;
use Test::Fatal;
use autobox::Core;
use Data::UUID;
use Readonly;

use aliased 'Net::Amazon::R53';
use aliased 'Net::Amazon::R53::HostedZone' => 'HZ';
use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

# NOTE we may need to account for taint mode here if asked
Readonly my $AWSID  => $ENV{AWS_ID};
Readonly my $AWSKEY => $ENV{AWS_KEY};

plan skip_all => 'live tests require AWS_ID and AWS_KEY to be set'
    unless $AWSID && $AWSKEY;

Readonly my $CALLER_REFERENCE => do { Data::UUID->new->create_str };
Readonly my $TEST_DOMAIN      => 'really.not.';

my $r53 = R53->new(id => $AWSID, key => $AWSKEY);
isa_ok $r53, R53;

note 'create our zone...';
my $hz = $r53->create_hosted_zone(
    name             => $TEST_DOMAIN,
    comment          => 'Test zone for R53 zone copy test @ ' . localtime,
    caller_reference => $CALLER_REFERENCE,
);
isa_ok $hz, HZ;

note 'create dummy records in scratch zone: ' . $hz->plain_id;
{
    my $_r = sub {
        return {
            name             => "example$_[0].$TEST_DOMAIN",
            type             => 'A',
            ttl              => 600,
            resource_records => [ '172.16.81.24' ],
        };
    };

    my @creates =
        map { { action => 'CREATE', record => $_ } }
        map { $_r->($_)                            }
        1..15
        ;

    my $change = $hz->submit_resource_records_change_request(
        comment        => 'create rrs in test zone for zone copy test',
        changes        => [ @creates ],
        multi_batch_ok => 1,
    );

    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';
}

note 'check record counts are as we expect...';
is $hz->resource_record_set_count,     15, '15 mutable records total';
is $hz->immutable_record_sets->length,  2, ' 2 immutable rrs found';

note 'copying our scratch zone via $r53->copy_zone...';
my $new_hz = $r53->copy_hosted_zone($hz);
isa_ok $new_hz, HZ;

note 'check record counts are as we expect in the zone copy...';
is $new_hz->resource_record_set_count,     15, '15 mutable records total';
is $new_hz->immutable_record_sets->length,  2, ' 2 immutable rrs found';

note 'purging and deleting our scratch zones...';
do { $_->purge; $r53->delete_hosted_zone($_->id) }
    for $hz, $new_hz;

done_testing;
