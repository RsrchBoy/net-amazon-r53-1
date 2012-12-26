package Net::Amazon::R53::ResourceRecordSet::Stub;

# ABSTRACT: A representation of a ResourceRecordSet

use utf8;

use Moose;
use MooseX::MarkAsMethods autoclean => 1;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints qw{ enum class_type };
use MooseX::AlwaysCoerce;
use MooseX::AttributeShortcuts 0.017;
use MooseX::Params::Validate;
use MooseX::Types::Moose ':all';
use MooseX::Types::Common::Numeric ':all';
use MooseX::Types::Common::String ':all';

use aliased 'MooseX::CoercePerAttribute';

use Data::Compare;

use overload
    '==' => sub {   shift->is_equivalent_to(shift) },
    '!=' => sub { ! shift->is_equivalent_to(shift) },
    fallback => 1,
    ;

with 'MooseX::Traitor';

# "anon" type constraint
use constant RecordType => enum [ qw{ A AAAA CNAME MX NS PTR SOA SPF SRV TXT } ];

# debugging...
#use Smart::Comments '###';

=reqatt name

Per the Route53 documentation, this is expected to always be a fully-qualified
domain name.  As such, we attempt to coerce by adding a '.' to the end of the
supplied name if not present.  This behaviour may change.

=reqatt type

One of the R53 supported types:

    A AAAA CNAME MX NS PTR SOA SPF SRV TXT

=attr ttl

=attr resource_records

=attr alias_target

=attr set_identifier

=attr weight

=attr region

=cut

has name => (
    traits     => [ CoercePerAttribute ],
    is         => 'ro',
    isa        => NonEmptySimpleStr,
    required   => 1,
    constraint => sub { /\.$/ },
    coerce => {
        NonEmptySimpleStr() => sub { "$_." },
    },
);

has type => (is => 'ro', isa => RecordType,        required  => 1);
has ttl  => (is => 'ro', isa => PositiveOrZeroInt, predicate => 1);

has resource_records => (is => 'ro', isa => 'ArrayRef[Str]', builder => sub { [ ] });

# alias sets only
has alias_target => (
    traits    => ['Hash'],
    is        => 'ro',
    isa       => HashRef[NonEmptySimpleStr],
    predicate => 1,
    handles   => {
        alias_target_hosted_zone_id => [ get => 'HostedZoneId' ],
        alias_target_dns_name       => [ get => 'DNSName'      ],
    },
);

# weighted + latency
has set_identifier => (is => 'ro', isa => 'Str', predicate => 1);

# weighted only
has weight => (
    is         => 'ro',
    isa        => PositiveOrZeroInt,
    constraint => sub { $_ < 256 },
    predicate  => 1,
);

# latency only
has region => (is => 'ro', isa => 'Str', predicate => 1);

=method new_from_net_dns_rr($rr, { %opts })

Takes a L<Net::DNS::RR> and creates a stub record instance off its type.

The C<%opts> optional argument is a hashref of additional options to pass to
our stub constructor; they will override anything we set.

Note that we _cannot_ take any Route53 specific record options here, as
L<Net::DNS> doesn't know anything about them.  Also, the L<Net::DNS::RR> being
passed in must be fully qualified; we don't have any good way to handle origin
right now, and simply append a '.' to C<$rr->name>.

=cut

sub new_from_net_dns_rr {
    my $class = shift @_;
    #my ($rr, $origin, $opts) = validated_list \@_,
    my ($rr, $opts) = validated_list \@_,
        rr     => { isa => class_type('Net::DNS::RR')                },
        #origin => { isa => NonEmptySimpleStr,         default => '.' },
        opts   => { isa => 'HashRef',                 default => { } },
        ;

    # this is made significantly easier in that if we're using a Net::DNS::RR
    # to create a stub, there will be no Route53-specific functionality
    # involved; so we'll always have a ttl (even if just 0), no alias or
    # weighted records, etc...

    confess 'Cannot convert a Net::DNS::RR with class: ' . $rr->class
        unless $rr->class eq 'IN';

    # fixup our origin; must start/stop with a .
    #$origin .= '.'        unless $origin =~ /\.$/;
    #$origin  = ".$origin" unless $origin =~ /^\./;

    # fixup our name; append $origin unless already fully-qualified
    my $name = $rr->name;
    # ## name and origin: "$name / $origin"
    #$name   .= $origin unless $name =~ /\.$/;
    $name .= '.' unless $name =~ /\.$/;

    my %params = (
        type => $rr->type,
        name => $name,
        ttl  => $rr->ttl || 0,

        resource_records => [
            $rr->rdatastr,
        ],
    );

    ### %params
    ### $opts

    %params = (%params, %$opts);
    return $class->new(%params);
}

=method is_equivalent_to($stub)

Given another stub, we check the records for equality.

=cut

sub is_equivalent_to {
    my ($self, $other) = @_;

    confess 'cannot compare with ' . ref $other
        unless $other->isa('Net::Amazon::R53::ResourceRecordSet::Stub');

    my $_eq  = sub { my $name = shift; $self->$name() eq $other->$name() };
    my $_peq = sub {
        my $name = shift;
        my $pred = "has_$name";

        my $self_has  = $self->$pred()  ? 1 : 0;
        my $other_has = $other->$pred() ? 1 : 0;

        return 1 if $self_has + $other_has == 0;
        return   if $self_has + $other_has == 1;

        return $self->$name().q{} eq $other->$name().q{};
    };

    # we could really do this in a nicer fashion by looking at the metaclasses
    # and using attribute tags to store how we should use them to compare.

    do { return unless $_eq->($_) }
        for qw{ name type };

    do{ return unless $_peq->($_) }
        for qw{ set_identifier weight region ttl };

    return unless Compare($self->alias_target, $other->alias_target);
};

__PACKAGE__->meta->make_immutable;
!!42;
__END__

=for stopwords ttl

=head1 DESCRIPTION

This class represents a R53 resource record set, "in the raw", as it were; a
record without an owning zone.  Stubs are useful both when specifing what a
R53 entry should look like, as well as for operations that just need the info,
and don't care if it's actually in an R53 hosted zone.

=head1 OVERVIEW

See the Amazon R53 API doc for legal values and uses, at the moment.

Note that we do basic validation here, and allow R53 itself to tell us when
values are off.

=cut
