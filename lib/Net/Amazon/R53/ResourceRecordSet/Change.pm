package Net::Amazon::R53::ResourceRecordSet::Change;

# ABSTRACT: A representation of a resource record set change

use Moose;
use namespace::autoclean;
use autobox::Core;
use MooseX::StrictConstructor;
use MooseX::AttributeShortcuts 0.017;
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose ':all';

use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';
use constant StubType     => class_type Stub;
use constant NetDNSRRType => class_type 'Net::DNS::RR';

use aliased 'MooseX::Types::VariantTable';

with 'MooseX::Traitor';
with 'Net::Amazon::R53::Role::ParentR53';

=reqatt action

The change to be performed; CREATE or DELETE.

=reqatt record

This is hashref of the record information; it is fed to the appropriate stub
class for validation, depending on the record_type above.

Legal types of data to feed record include the aforementioned HashRef and any
instance of L<Net::Amazon::R53::ResourceRecordSet::Stub> or any subclass
thereof.

=cut

has action => (
    is       => 'ro',
    isa_enum => [ qw{ CREATE DELETE } ],
    required => 1,
);

# XXX why am I not using coercions here?!

has raw_record => (
    is       => 'ro',
    isa      => union([ HashRef, StubType, NetDNSRRType ]),
    init_arg => 'record',
    required => 1,
);

has record => (
    is       => 'lazy',
    isa      => StubType,
    init_arg => undef,
    builder  => 1,
);

sub _build_record {
    my $self = shift @_;

    my $raw        = $self->raw_record;
    my $stub_class = $self->resource_record_set__stub_class;

    return $raw
        if blessed $raw && $raw->isa(Stub);

    return $stub_class->new_from_net_dns_rr($raw)
        if blessed $raw && $raw->isa('Net::DNS::RR');

    #return $self->resource_record_set__stub_class->new($self->raw_record);
    return $stub_class->new($self->raw_record);
}

# TODO this should be a nicer way to dispatch vs the present method
#has _record_builder_table => (
    #is => 'lazy',
    ## TODO isa
    ## TODO handles   
#);

#sub _build__record_builder_table {
    #my $self = shift @_;

    #VariantTable->new(variants => [
        #{
            #type => class_type('Net::DNS::RR'),
            #value => sub { $self->_from_net_dns_rr(@_) },
        #},
        #{
            #type => class_type(

__PACKAGE__->meta->make_immutable;
!!42;
__END__
