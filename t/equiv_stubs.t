use strict;
use warnings;

# check stub equality tests

use Test::More;

use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

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

ok  $stub1a->is_equivalent_to($stub1b), 'equiv correct';
ok !$stub1a->is_equivalent_to($stub2a), 'equiv correct';
ok !$stub1a->is_equivalent_to($stub3a), 'equiv correct';
ok !$stub1a->is_equivalent_to($stub4a), 'equiv correct';
ok !$stub1a->is_equivalent_to($stub5a), 'equiv correct';

ok  $stub2a->is_equivalent_to($stub2b), 'equiv correct';
ok !$stub2a->is_equivalent_to($stub1a), 'equiv correct';
ok !$stub2a->is_equivalent_to($stub3a), 'equiv correct';
ok !$stub2a->is_equivalent_to($stub4a), 'equiv correct';
ok !$stub2a->is_equivalent_to($stub5a), 'equiv correct';

ok  $stub3a->is_equivalent_to($stub3b), 'equiv correct';
ok !$stub3a->is_equivalent_to($stub1a), 'equiv correct';
ok !$stub3a->is_equivalent_to($stub2a), 'equiv correct';
ok !$stub3a->is_equivalent_to($stub4a), 'equiv correct';
ok !$stub3a->is_equivalent_to($stub5a), 'equiv correct';

ok  $stub4a->is_equivalent_to($stub4b), 'equiv correct';
ok !$stub4a->is_equivalent_to($stub1a), 'equiv correct';
ok !$stub4a->is_equivalent_to($stub2a), 'equiv correct';
ok !$stub4a->is_equivalent_to($stub3a), 'equiv correct';
ok !$stub4a->is_equivalent_to($stub5a), 'equiv correct';

ok  $stub5a->is_equivalent_to($stub5b), 'equiv correct';
ok !$stub5a->is_equivalent_to($stub1a), 'equiv correct';
ok !$stub5a->is_equivalent_to($stub2a), 'equiv correct';
ok !$stub5a->is_equivalent_to($stub3a), 'equiv correct';
ok !$stub5a->is_equivalent_to($stub4a), 'equiv correct';

# overload testing

cmp_ok $stub1a, '==', $stub1b, 'overloading == worked as expected';
cmp_ok $stub1a, '!=', $stub2a, 'overloading != worked as expected';

done_testing;
