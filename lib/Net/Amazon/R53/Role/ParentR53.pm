package Net::Amazon::R53::Role::ParentR53;

# ABSTRACT: A role bestowing a parent link

use Moose::Role;
use utf8;
use namespace::autoclean;

=reqatt r53

The L<Net::Amazon::R53> this class belongs to.

=cut

my $_same = sub { $_[0] => $_[0] };

has r53 => (
    is       => 'ro',
    isa      => 'Net::Amazon::R53',
    required => 1,

    # TODO strictly for now -- need to autoconstruct role to provide the correct
    # parent attributes for us related classes
    handles => [ qw{
        atomic_change_class
        change_info_class
        resource_record_set_class
        resource_record_set__stub_class
        resource_record_set__change_class
    } ],
);

!!42;
