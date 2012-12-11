use strict;
use warnings;

use Test::More;
use Test::Fatal;

use autobox::Core;

use Data::UUID;
use Readonly;
use Net::Amazon::R53;

# NOTE we may need to account for taint mode here if asked
Readonly my $AWSID  => $ENV{AWS_ID};
Readonly my $AWSKEY => $ENV{AWS_KEY};

plan skip_all => 'live tests require AWS_ID and AWS_KEY to be set'
    unless $AWSID && $AWSKEY;

Readonly my $CALLER_REFERENCE => do { Data::UUID->new->create_str };
Readonly my $TEST_DOMAIN      => 'really.not.';

# XXX I suspect this could be handled better with Test::Routine
my ($hz_id, @scratch_zones);
sub _r53 { Net::Amazon::R53->new(id => $AWSID, key => $AWSKEY) }

{
    no warnings 'redefine';
    sub subtest { local $_[0] = "[subtest result] $_[0]"; goto \&Test::More::subtest }
}

subtest 'create zone' => sub {

    my $r53 = _r53;
    my $caller_ref = Data::UUID->new->create_str;

    my ($hz, $change);
    my $death_message = exception {
        ($hz, $change) = $r53->create_hosted_zone(
            #caller_reference => $caller_ref,
            caller_reference => $CALLER_REFERENCE,
            name             => $TEST_DOMAIN,
            comment          => 'Test zone for ' . localtime,
        );
    };

    is $death_message, undef, 'creating zone did not die!';
    isa_ok $hz, 'Net::Amazon::R53::HostedZone';
    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';

    # stash these for usage by the other tests.
    $hz_id = $hz->plain_id;
    push @scratch_zones, $hz->plain_id;

    return;
};

subtest 'pristine zone' => sub {

    #plan skip_all => 'wip';
    my $r53 = _r53;
    my $hz = $r53->hosted_zone($hz_id);

    isa_ok $hz, 'Net::Amazon::R53::HostedZone';
    is $hz->resource_record_set_count,     0, '0 mutable records total';
    is $hz->immutable_record_sets->length, 2, '2 immutable rrs found';
    is $hz->resource_record_set_count,     0, '0 mutable records total';
    ok !$hz->has_resource_record_sets, 'we do not have mutable resource record sets';

    ok $hz->is_pristine_zone, 'zone is pristine';

    return;
};

subtest 'add/delete rrs from zone' => sub {

    my $r53 = _r53;
    ok $r53->has_hosted_zone($hz_id), 'has our scratch hosted zone';
    my $hz = $r53->hosted_zone($hz_id);
    isa_ok $hz, 'Net::Amazon::R53::HostedZone';

    my $resource = {
        name             => "example.$TEST_DOMAIN",
        type             => 'A',
        ttl              => 600,
        resource_records => [ '172.16.81.24' ],
    };

    my $change = $hz->submit_resource_records_change_request(
        comment => 'testing solo add',
        changes => [
            { action => 'CREATE', record => $resource },
        ],
    );

    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';

    $change = $hz->submit_resource_records_change_request(
        comment => 'testing solo delete',
        changes => [
            { action => 'DELETE', record => $resource },
        ],
    );

    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';

    return;
};

subtest 'delete rrs using rrs as record' => sub {

    my $r53 = _r53;
    ok $r53->has_hosted_zone($hz_id), 'has our scratch hosted zone';
    my $hz = $r53->hosted_zone($hz_id);
    isa_ok $hz, 'Net::Amazon::R53::HostedZone';

    ok !$hz->has_resource_record_sets, 'we have no rrs in our zone';

    my $resource = {
        name             => "example.$TEST_DOMAIN",
        type             => 'A',
        ttl              => 600,
        resource_records => [ '172.16.81.24' ],
    };

    my $change = $hz->submit_resource_records_change_request(
        comment => 'testing solo add',
        changes => [
            { action => 'CREATE', record => $resource },
        ],
    );

    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';

    ok $hz->has_resource_record_sets, 'we do have rrs in our zone now';

    my $rrs = $hz->resource_record_sets->[0];

    $change = $hz->submit_resource_records_change_request(
        comment => 'testing solo delete',
        changes => [
            { action => 'DELETE', record => $rrs },
        ],
    );

    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like $change->status, qr/^(PENDING|INSYNC)$/, 'delete operation OK';

    return;
};

subtest '> 100 RRS' => sub {

    my $r53 = _r53;
    my $hz = $r53->hosted_zone($hz_id);
    ok !$hz->has_resource_record_sets, 'we have no (mutable) rrs in our zone';
    ok $hz->has_fetched_resource_record_sets, 'we have fetched rrs data';

    my $_r = sub {
        return {
            name             => "example$_[0].$TEST_DOMAIN",
            type             => 'A',
            ttl              => 600,
            resource_records => [ '172.16.81.24' ],
        };
    };

    my @records = map { $_r->($_) } 1..150;
    my @creates = map { { action => 'CREATE', record => $_ } } @records;
    my @deletes = map { { action => 'DELETE', record => $_ } } @records;

    subtest '>100 RRS creation' => sub {
        my $msg = exception {
            my $change = $hz->submit_resource_records_change_request(
                comment => 'create > 100 test -- should fail',
                changes => [ @creates ],
            );
        };
        like $msg, qr/Batch is > 100, but multi_batch_ok is not set!/, 'dies ok';
        my $change = $hz->submit_resource_records_change_request(
            comment        => 'create > 100 test',
            changes        => [ @creates ],
            multi_batch_ok => 1,
        );
        isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
        like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';
    };

    subtest '>100 retrieval' => sub {
        $hz->clear_resource_record_sets;
        is $hz->resource_record_set_count, 150, 'rrs count correct (150)';
    };

    subtest '>100 RRS deletion' => sub {
        my $msg = exception {
            my $change = $hz->submit_resource_records_change_request(
                comment => 'delete > 100 test -- should fail',
                changes => [ @deletes ],
            );
        };
        like $msg, qr/Batch is > 100, but multi_batch_ok is not set!/, 'dies ok';
        my $change = $hz->submit_resource_records_change_request(
            comment        => 'delete > 100 test -- should pass',
            changes        => [ @deletes ],
            multi_batch_ok => 1,
        );
        isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
        like $change->status, qr/^(PENDING|INSYNC)$/, 'delete operation OK';
        ok !$hz->has_fetched_resource_record_sets, 'rrs attribute cleared OK';
        is $hz->resource_record_set_count, 0, 'rrs count correct (0)';
    };

    subtest 'purge zone' => sub {
        my $change = $hz->submit_resource_records_change_request(
            comment        => 'create > 100 test',
            changes        => [ @creates ],
            multi_batch_ok => 1,
        );
        isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
        like $change->status, qr/^(PENDING|INSYNC)$/, 'add operation OK';
        $change = $hz->purge;
        isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
        like $change->status, qr/^(PENDING|INSYNC)$/, 'delete operation OK';
        ok !$hz->has_fetched_resource_record_sets, 'rrs attribute cleared OK';
        is $hz->resource_record_set_count, 0, 'rrs count correct (0)';
    };

    return;
};

subtest 'get zone listing' => sub {

    my $r53 = _r53;

    ok $r53->has_hosted_zones, 'we have hosted zones';
    cmp_ok $r53->hosted_zones_count,  '>', 0, 'one or more hosted zones found';
    ok $r53->has_hosted_zone($hz_id), "found our scratch hosted zone: $hz_id";
    my $hz = $r53->hosted_zone($hz_id);
    isa_ok $hz, 'Net::Amazon::R53::HostedZone';

    note 'checking caller reference lookups: ' . $hz->caller_reference;
    my $hz_by_ref = $r53->hosted_zone_by_caller_reference($hz->caller_reference);
    is $hz_by_ref->caller_reference, $hz->caller_reference, 'fetched by caller reference';
    $hz_by_ref = $r53->hosted_zone_by_caller_reference('Run! Daleks!');
    is $hz_by_ref, undef, 'correctly returns nothing when not found';

    return;
};

subtest 'delete zone' => sub {

    #plan skip_all => 'delete zone not implemented yet';
    my $r53 = _r53;

    note "deleting hosted zone: $hz_id";

    # force our hostedzone attribute to be populated
    ok !$r53->has_fetched_hosted_zones, 'hosted zones have not been fetched';
    cmp_ok $r53->hosted_zones_count,  '>', 0, 'more than 0 hosted zones found';
    ok $r53->has_hosted_zone($hz_id), "zone list contains $hz_id";

    my $change;
    my $death_msg = exception { $change = $r53->delete_hosted_zone($hz_id) };
    is $death_msg, undef, "deletion didn't die";
    isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
    like
        $change->status,
        qr/^(INSYNC|PENDING)/,
        'deletion request is in a successful state',
        ;

    ok !$r53->has_hosted_zone($hz_id),
        "zone list does not contain deleted zone $hz_id",
        ;

    return;
};


#subtest 'create rrs'
#subtest 'delete rrs'
#subtest 'purge rrs'
#subtest 'atomic replace'
#subtest 'batch change'
#subtest 'clone hz'


done_testing;
