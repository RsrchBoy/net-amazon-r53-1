package Net::Amazon::R53::HostedZone;

# ABSTRACT: Representation of a Route53 HostedZone

use v5.10;
use utf8;

use Moose;
use autobox::Core;
use namespace::autoclean;
use Moose::Util::TypeConstraints qw{ class_type union };
use MooseX::AlwaysCoerce;
use MooseX::AttributeShortcuts 0.017;
use MooseX::CascadeClearing;
use MooseX::Params::Validate;
use MooseX::StrictConstructor;
use MooseX::Types::Moose ':all';
use MooseX::Types::Common::Numeric ':all';
use MooseX::Types::Common::String  ':all';

use List::AllUtils 'natatime';

use constant RRSChangeType => class_type 'Net::Amazon::R53::ResourceRecordSet::Change';
use constant RRSType       => class_type 'Net::Amazon::R53::ResourceRecordSet';
use constant ArrayOfRRS    => do { ArrayRef[RRSType] };

use XML::Simple;

# debugging...
#use Smart::Comments '####';

with 'MooseX::Traitor';
with
    'Net::Amazon::R53::Role::NewFromRawData',
    'Net::Amazon::R53::Role::ParentR53',
    ;


=reqatt r53

=reqatt caller_reference

=reqatt config

=reqatt id

=reqatt name

=reqatt resource_record_set_count

This attribute reflects the number of mutable records; which will always be
two less than the total number.  Accordingly, this number is adjusted down two
from the raw count returned from Route53 in a hosted zone query.

=cut

has caller_reference => (is => 'ro', isa => NonEmptySimpleStr, required => 1);
has config           => (is => 'ro', isa => 'ArrayRef',        builder  => sub { [ ] });
has id               => (is => 'ro', isa => NonEmptySimpleStr, required => 1);
has name             => (is => 'ro', isa => NonEmptySimpleStr, required => 1);

has resource_record_set_count => (
    is           => 'rwp',
    isa          => PositiveOrZeroInt,
    lazy         => 1,
    required     => 1,
    clearer      => -1,
    predicate    => -1,
    clear_master => 'resource_record_sets',
    # see CMOP::Attribute docs for initalizer
    # initializer WILL FIRE on builders too (wtf?!)
    initializer  => sub { $_[2]->($_[1]-2) },
    builder      => sub { shift->_rrss_count },
);

=lazyatt plain_id

The full hosted zone ID Amazon returns looks something like:

    /hostedzone/ZAJ312RFF552

However, most operations (and indeed, this library) use just the last part:

    ZAJ312RFF552

This attribute builds the short form for you on demand.

=cut

has plain_id => (
    is      => 'lazy',
    isa     => NonEmptySimpleStr,
    builder => sub { shift->id->split(qr!/!)->pop },
);

=lazyatt immutable_record_sets

Contains the set of two Amazon-created records that lead every host zone's
record set set.

=lazyatt resource_record_sets

Contains this hosted zone's last fetched set of resource records.  This set
does not include the Amazon-supplied "immutable" ones.

=method clear_reset_record_sets

Clears our cached set of resource records.  (Will be rebuilt on next access)

=method has_fetched_resource_record_sets

True if the resource records for this zone have been fetched.  Useful to
determine if this has happened without calling anything that may cause the
fetch operation to be executed.

=method is_pristine_zone

Returns true if the zone contains no resource record sets other than the
immutable ones Amazon supplies.  A "pristine" zone can be deleted.

=cut

# Yes, the assumption here is that the first two RRS are always the
# amazon-immutable ones.  I don't think this is a dangerous assumption to
# make, particularly with this level of the API.

has immutable_record_sets => (
    is           => 'rwp',
    isa          => ArrayOfRRS,
    lazy         => 1,
    clearer      => -1,
    clear_master => 'resource_record_sets',
    builder      => sub { [ $_[0]->_rrs(0), $_[0]->_rrs(1) ] },
);

has resource_record_sets => (
    traits          => ['Array'],
    is              => 'rwp',
    isa             => ArrayOfRRS,
    lazy            => 1,
    clearer         => 1,
    is_clear_master => 1,
    builder         => sub { my @r = shift->_rrss; shift @r for 1..2; \@r },
    handles => {
        has_resource_record_sets   => 'count',
        resource_record_set        => 'get',
        is_pristine_zone           => 'is_empty',
        _add_resource_record_set   => 'push',
        _resource_record_set_count => 'count',
    },
);

# This is the "real" list of resource record sets.  we're set up such that the
# two attributes above use this attribute to provide their data, so either
# one being built will trigger this one.  Likewise, the only public clearer
# either three of these have is clear_resource_record_sets, but that's
# cascaded out to the other two attributes, so calling that clearer will
# actually clear all three of these attributes.

has _all_rrs => (
    traits       => ['Array'],
    is           => 'lazy',
    isa          => ArrayOfRRS,
    clearer      => -1,
    predicate    => 'has_fetched_resource_record_sets',
    clear_master => 'resource_record_sets',
    handles      => {
        _rrss       => 'elements',
        _rrs        => 'get',
        _rrss_count => 'count',
    },
);

sub _build__all_rrs {
    my $self = shift @_;

    $self->_clear_resource_record_set_count;
    return $self->r53->get_resource_record_sets($self->plain_id);
}

=method apply_atomic_change($ac)

Given an L<AtomicChange|Net::Amazon::R53::AtomicChange> instance, apply the
changes described to this hosted zone.

=cut

sub apply_atomic_change {
    my ($self, $ac) = @_;

    die 'an AtomicChange instance must be presented'
        unless blessed $ac && $ac->isa('Net::Amazon::R53::AtomicChange');

    my $change = $self->submit_resource_records_change_request(
        comment        => 'Atomic changeset',
        changes        => $ac->changes,
        multi_batch_ok => 0,
    );

    return $change;
}

=method submit_resource_records_change_request(comment => ..., changes => [ ... ])

Takes a set of either L<Net::Amazon::R53::ResourceRecordSet::Change> or
array references suitable to passing to that class' constructor.  We return
a L<Net::Amazon::R53::ChangeInfo> instance representing the submitted change.

On failure, we throw an error.

=head3 multi_batch_ok

We also accept a C<multi_batch_ok> option, that defaults to false.  If set
true, change sets with greater than 100 changes are broken up and submitted as
multiple requests, in batches of no more than 100 changes at a time.

If we're called in list context, we return the list of change-info objects
returned from the multiple operations.  If we're called in scalar context, we
return the last of the returned info objects.

=cut

sub submit_resource_records_change_request {
    my $self = shift @_;

    my ($comment, $changes, $multi_batch_ok) = validated_list \@_,
        comment        => { isa => 'Str', default => 'Batch change API initiated' },
        changes        => { isa => ArrayRef [ union [ RRSChangeType, HashRef ] ]  },
        multi_batch_ok => { isa => Bool, default => 0                             },
        ;

    confess 'Batch is > 100, but multi_batch_ok is not set!'
        if $changes->length > 100 && !$multi_batch_ok;

    my $cclass = $self->resource_record_set__change_class;

    do { $_ = $cclass->new(%$_, r53 => $self->r53) unless blessed $_ }
        for @$changes;

    my $part = 'hostedzone/' . $self->plain_id . '/rrset';
    my $tmpl = 'batch_rrs_change.tt';
    my @info = ();
    my $it   = natatime 100, @$changes;

    while (my @changes_chunk = $it->()) {

        ### issuing batch change command...
        $self->r53->tt->process(
            $tmpl,
            { comment => $comment, changes => [ @changes_chunk ] },
            \(my $req_content),
        ) || confess $self->r53->tt->error;

        ### $req_content
        my $resp = $self->r53->post_request($part, $req_content);

        ### response: $resp->content
        my $info_returned = XMLin($resp->content);
        push @info, $self
            ->change_info_class
            ->new_from_raw_data($self->r53, $info_returned->{ChangeInfo})
            ;
    }

    ### remove existing and return the change record...
    $self->clear_resource_record_sets;
    return @info if wantarray;
    return pop @info;
}

=head2 purge

Delete all records from the zone that Route53 requires to be removed before
the zone may be deleted.  (That is, all records save the two "immutable" first
records, the Route53-generated NS and SOA records.)

=cut

sub purge {
    my $self = shift @_;

    return unless $self->has_resource_record_sets;

    my @changes =
        map { { action => 'DELETE', record => $_ } }
        $self->resource_record_sets->flatten
        ;

    return $self->submit_resource_records_change_request(
        comment        => 'zone-purge requested',
        changes        => \@changes,
        multi_batch_ok => 1,
    );
}

__PACKAGE__->meta->make_immutable;
!!42;
__END__

=for :stopwords SOA

=head1 DESCRIPTION

This class represents a Route53 hosted zone entity.  You should never
need to construct this class yourself, as the parent will do it for you when
appropriate.

=cut
