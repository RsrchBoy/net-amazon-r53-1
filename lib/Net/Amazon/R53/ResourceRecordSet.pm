package Net::Amazon::R53::ResourceRecordSet;

# ABSTRACT: A representation of a ResourceRecordSet

use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints 'enum';
use MooseX::AlwaysCoerce;
use MooseX::AttributeShortcuts 0.017;
use MooseX::Types::Moose ':all';
use MooseX::Types::Common::Numeric ':all';
use MooseX::Types::Common::String ':all';

extends 'Net::Amazon::R53::ResourceRecordSet::Stub';

with 'MooseX::Traitor';
with
    'Net::Amazon::R53::Role::NewFromRawData',
    'Net::Amazon::R53::Role::ParentR53',
    ;

has r53_rrs_type => (
    is  => 'lazy',
    isa => enum [ qw{ standard alias weighted weighted_latency latency } ],
);

# XXX this feels... bad

sub _build_r53_rrs_type {
    my $self = shift @_;

    my $has_set_id  = $self->has_set_identifier;
    my $has_alias   = $self->has_alias_target;
    my $has_weight  = $self->has_weight;
    my $has_region  = $self->has_region;

    return 'standard'
        unless $has_set_id || $has_alias || $has_weight || $has_region;

    if ($has_alias) {

        confess 'invalid rrs type'
            if $has_set_id || $has_weight || $has_region;

        return 'alias';
    }

    ### assert: !$has_alias;

    # at least one remaining is false
    confess 'invalid rrs type'
        if $has_region && $has_set_id && $has_weight;

    return 'weighted_latency'
        if $has_weight && $has_set_id;

    ### assert: !$has_region

    return 'weighted'
        if $has_weight;

    ### assert: $has_region
    return 'latency';
}

sub is_standard_record_set   { shift->r53_rrs_type eq 'standard' }

__PACKAGE__->meta->make_immutable;
!!42;
__END__
