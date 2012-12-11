use strict;
use warnings;

use Test::More;
use Test::Fatal;
use autobox::Core;
use Readonly;

use Net::Amazon::R53;

# NOTE we may need to account for taint mode here if asked
Readonly my $AWSID  => $ENV{AWS_ID};
Readonly my $AWSKEY => $ENV{AWS_KEY};

plan skip_all => 'live tests require AWS_ID and AWS_KEY to be set'
    unless $AWSID && $AWSKEY;

Readonly my $TEST_DOMAIN      => 'really.not.';

my  $r53 = Net::Amazon::R53->new(id => $AWSID, key => $AWSKEY);


my ($hz, $change);
my $death_message = exception {
    ($hz, $change) = $r53->create_hosted_zone(
        name             => $TEST_DOMAIN,
        comment          => 'Test zone for ' . localtime,
    );
};

is $death_message, undef, 'creating zone did not die!';
isa_ok $hz, 'Net::Amazon::R53::HostedZone';
isa_ok $change, 'Net::Amazon::R53::ChangeInfo';

note 'zone id: ' . $hz->id;
note 'zone caller reference: ' . $hz->caller_reference;

ok !!($hz->caller_reference), 'we have a caller reference';

note 'deleting hosted zone: ' . $hz->id;

my $death_msg = exception { $change = $r53->delete_hosted_zone($hz->id) };
is $death_msg, undef, "deletion didn't die";
isa_ok $change, 'Net::Amazon::R53::ChangeInfo';
like
    $change->status,
    qr/^(INSYNC|PENDING)/,
    'deletion request is in a successful state',
    ;

ok !$r53->has_hosted_zone($hz->id),
    'zone list does not contain deleted zone ' . $hz->id,
    ;

done_testing;
