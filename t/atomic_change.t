use strict;
use warnings;

# check stub equality tests

use Test::More;
use Moose::Autobox;

# debugging...
#use Smart::Comments '###';

use aliased 'Net::Amazon::R53';
use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';
use aliased 'Net::Amazon::R53::AtomicChange';

my $stub1a = Stub->new(type => 'A', ttl => 600, name => 'name.thing.ie.');
my $stub1b = Stub->new(type => 'A', ttl => 600, name => 'name.thing.ie.');

my $stub2a = Stub->new(type => 'A', ttl => 550, name => 'name.thing.ie.');
my $stub2b = Stub->new(type => 'A', ttl => 550, name => 'name.thing.ie.');

my $stub3a = Stub->new(name => 'name.thing.ie.', type => 'A', alias_target => { one => 1, two => 2 }, weight => 10);
my $stub3b = Stub->new(name => 'name.thing.ie.', type => 'A', alias_target => { one => 1, two => 2 }, weight => 10);

my $stub4a = Stub->new(name => 'name.thing.ie.', type => 'A', set_identifier => 'la la la', weight => 10);
my $stub4b = Stub->new(name => 'name.thing.ie.', type => 'A', set_identifier => 'la la la', weight => 10);

my $stub5a = Stub->new(name => 'name.thing.ie.', type => 'A', set_identifier => 123, weight => 10);
my $stub5b = Stub->new(name => 'name.thing.ie.', type => 'A', set_identifier => 123, weight => 10);

my $r53 = R53->new(id => 'foo', key => 'bar');

subtest 'only alpha' => sub {

    my $ac = AtomicChange->new(r53 => $r53, alpha => [ $stub1a ], omega => []);
    isa_ok $ac, AtomicChange;

    is $ac->to_create->length, 0, 'correct to_create count';
    is $ac->to_delete->length, 1, 'correct to_delete count';
    is $ac->changes->length,   1, 'correct total change count';

    ### $ac

    my $to_create = $ac->to_create;
    ### $to_create

    return;
};

subtest 'only omega' => sub {

    my $ac = AtomicChange->new(r53 => $r53, alpha => [], omega => [ $stub1a ]);
    isa_ok $ac, AtomicChange;

    is $ac->to_create->length, 1, 'correct to_create count';
    is $ac->to_delete->length, 0, 'correct to_delete count';
    is $ac->changes->length,   1, 'correct total change count';

    return;
};

subtest 'equality test sanity check' => sub {

    my $ac = AtomicChange->new(
        r53   => $r53,
        alpha => [ $stub1b, $stub2b, $stub3b, $stub4b, $stub5b ],
        omega => [ $stub1a, $stub2a, $stub3a, $stub4a, $stub5a ],
    );
    isa_ok $ac, AtomicChange;

    is $ac->to_create->length, 0, 'correct to_create count';
    is $ac->to_delete->length, 0, 'correct to_delete count';
    is $ac->changes->length,   0, 'correct total change count';

    return;
};

subtest 'alpha and omega overlapping' => sub {

    my $ac = AtomicChange->new(
        r53   => $r53,
        alpha => [ $stub1a, $stub2a ],
        omega => [ $stub1b, $stub3a ],
    );
    isa_ok $ac, AtomicChange;

    is $ac->to_create->length, 1, 'correct to_create count';
    cmp_ok $ac->to_create->first, '==', $stub3a, 'correct create list';
    is $ac->to_delete->length, 1, 'correct to_delete count';
    cmp_ok $ac->to_delete->first, '==', $stub2a, 'correct delete list';

    return;
};

subtest 'alpha is omega' => sub {

    my $ac = AtomicChange->new(
        r53   => $r53,
        alpha => [ $stub1a ],
        omega => [ $stub1b ],
    );
    isa_ok $ac, AtomicChange;

    ok $ac->has_no_changes,       'correctly reports no changes';
    is $ac->to_create->length, 0, 'correct to_create count';
    is $ac->to_delete->length, 0, 'correct to_delete count';

    return;
};

done_testing;
