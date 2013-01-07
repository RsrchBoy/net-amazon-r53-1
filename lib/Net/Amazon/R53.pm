package Net::Amazon::R53;

# ABSTRACT: An interface to Amazon's Route53

use utf8;
use v5.10;

use Moose;
use namespace::autoclean;
use autobox::Core;
use MooseX::AlwaysCoerce;
use MooseX::AttributeShortcuts 0.017;
use MooseX::Params::Validate;
use MooseX::Types::Common::String ':all';
use MooseX::Types::Path::Class ':all';

use Data::UUID;
use File::ShareDir::ProjectDistDir;
use HTTP::Request;
use List::AllUtils 'first';
use LWP::UserAgent;
use Template;
use XML::Simple;

use aliased 'Net::Amazon::Signature::V3';

# debugging...
#use Smart::Comments '###';

with 'MooseX::RelatedClasses' => {
    names => [ qw{
        AtomicChange
        ChangeInfo
        HostedZone
        ResourceRecordSet
        ResourceRecordSet::Stub
        ResourceRecordSet::Change
    } ],
};

=reqatt id

Your AWS id.

=reqatt key

...and the corresponding AWS secret key.

=cut

has $_ => (is => 'ro', required => 1, isa => NonEmptySimpleStr)
    for qw{ id key };

=lazyatt signer

The logic that authenticates your requests to Route53.

=method signed_headers

Returns a list of headers (key/value pairs) suitable for direct inclusion in
the headers of a Route53 request.

=cut

has signer => (
    is      => 'lazy',
    isa     => 'Net::Amazon::Signature::V3',
    builder => sub { V3->new(id => $_[0]->id, key => $_[0]->key) },
);

has ua => (
    is      => 'lazy',
    isa     => 'LWP::UserAgent',
    builder => sub { LWP::UserAgent->new },
);

has endpoint_base => (
    is      => 'lazy',
    isa     => NonEmptySimpleStr,
    builder => sub { 'https://route53.amazonaws.com/2012-02-29/' },
);

=attr hosted_zones_hash

Contains a list of all C<HostedZones> associated with this AWS key/id; lazily
built.  Right now we fetch at most 100 records.

=method has_fetched_hosted_zones

True if the C<hosted_zones> attribute is currently populated (that is, we've
fetched some at some point from Amazon.

=method clear_hosted_zones

Deletes our cached set of hosted zones, if we have any.

=method has_hosted_zones

True if we currently have any hosted zones.

=method has_hosted_zone($plain_id)

True if we have a zone with a plain id as passed to us.

=method hosted_zone_ids

Returns all of the hosted zone ids we know about.

=method hosted_zones

Returns a list of all known hosted zones; that is, a list of
L<Net::Amazon::R53::HostedZone> instances.

=method hosted_zones_count

Returns the number of hosted zones Route53 thinks we have.
=method hosted_zone_by_id($id)

Looks for a hosted zone with the passed value as its id.  Note that we're
talking about the so-called "plain" id, not the fully qualified one (e.g.
'Z12345', not '/hostedzone/Z12345').

=cut

has hosted_zones_hash => (
    traits    => ['Hash'],
    is        => 'lazy',
    isa       => 'HashRef[Net::Amazon::R53::HostedZone]',
    clearer   => 1,
    predicate => 'has_fetched_hosted_zones',
    handles   => {
        # predicate not for the attribute, but content
        has_hosted_zones    => 'count',
        has_hosted_zone     => 'exists',
        hosted_zone_ids     => 'keys',
        hosted_zones        => 'values',
        hosted_zone         => 'get',
        hosted_zone_by_id   => 'get',
        hosted_zones_count  => 'count',
        _add_hosted_zone    => 'set',
        _delete_hosted_zone => 'delete',
    },
);

sub _build_hosted_zones_hash {
    my $self = shift @_;

    my $part = 'hostedzone?maxitems=100';
    my $resp = $self->get_request($part, undef);

    ### parsing content: $resp->content
    my $zones = XMLin(
        $resp->content,
        ForceArray => [ qw{ HostedZone Config } ],
        GroupTags  => { HostedZones => 'HostedZone' },
    );

    ### $zones
    my $hz_class = $self->hosted_zone_class;
    my @zones =
        map { $hz_class->new_from_raw_data($self, $_) }
        $zones->{HostedZones}->flatten
        ;

    return { map { $_->plain_id => $_ } @zones };
}

=method hosted_zone_by_caller_reference($caller_reference)

Looks for a zone with the passed string as its caller reference.  Returns
nothing if no such zone is found.

=cut

sub hosted_zone_by_caller_reference {
    my ($self, $caller_ref) = @_;

    # implementation note: caller references are guaranteed unique by Amazon,
    # so using first() here isn't going to have any weird side-effects.

    ### searching for: $caller_ref
    my $hz =
        first { $_->caller_reference eq $caller_ref }
        $self->hosted_zones
        ;

    return $hz;
}

=method get_resource_record_sets(<hosted zone id>)

Given a hosted zone id, we fetch all its associated resource record sets.

=cut

# TODO move into HZ class?
sub get_resource_record_sets {
    my ($self, $hz_id) = @_;

    ### fetching records for hostedzone: $hz_id
    my $base_part = my $part = "hostedzone/$hz_id/rrset?maxitems=100";
    my @unparsed_rrs;

    while (1) {

        ### getting rrs via: $part
        my $resp = $self->get_request($part, undef);

        ### parsing content: $resp->content
        my $rrs_set = XMLin(
            $resp->content,
            ForceArray => [ qw{ ResourceRecordSet ResourceRecord } ],
            GroupTags  => {
                ResourceRecordSets => 'ResourceRecordSet',
                ResourceRecords    => 'ResourceRecord',
            },
        );

        # I can't _quite_ figure out how to get XML::Simple to do this for me
        $rrs_set->{ResourceRecordSets} ||= [];
        for my $rrs ($rrs_set->{ResourceRecordSets}->flatten) {

            next unless $rrs->{ResourceRecords};
            my @values =
                map { $_->{Value} }
                $rrs->{ResourceRecords}->flatten;
            $rrs->{ResourceRecords} = \@values;
        }

        push @unparsed_rrs, $rrs_set->{ResourceRecordSets}->flatten;

        last unless $rrs_set->{IsTruncated} eq 'true';

        # prep and create our next part...
        my $query = q{};
        my $_val   = sub { $rrs_set->{'NextRecord' . $_[0]->ucfirst} };

        do { $query .= "&$_=" . $_val->($_) if $_val->($_) }
            for qw{ name type identifier };

        $part = $base_part . $query;
    }

    my @rrs =
        map { $self->resource_record_set_class->new_from_raw_data($self, $_) }
        @unparsed_rrs
        ;

    return \@rrs;
}

=method create_hosted_zone(name => ..., caller_reference => ..., comment => ...)

Creates a hosted zone.

C<name> is the domain name this zone holds records for, e.g. 'test.com.'.

C<caller_reference> is some unique client-chosen (aka you) identifier.

C<comment> is, well, the comment used for zone creation.

Only the C<name> parameter is mandatory; suitable values will be generated for
the other options if they are omitted.

Returns the new hosted zone object if called in scalar context; the change
and hosted zone objects if called in list context; that is:

    my ($hz, $change) = $r53->create_hosted_zone(...);
    my $hz            = $r53->create_hosted_zone(...);

Dies on error.  For more information, see the Route53 API and Developer's
Guide.

=cut

sub create_hosted_zone {
    my $self = shift @_;

    my %opts = validated_hash(\@_,
        name             => { isa => 'Str'                },
        comment          => { isa => 'Str', optional => 1 },
        caller_reference => { isa => 'Str', optional => 1 },
    );

    # MX::Params::Validate doesn't deal with dynamic defaults very well yet

    $opts{comment} //= 'Created ' . localtime;
    $opts{caller_reference} //= Data::UUID->new->create_str;

    my $part = 'hostedzone';
    my $tmpl = 'create_hosted_zone.tt';

    $self->tt->process('create_hosted_zone.tt', { %opts }, \(my $req_content));

    ### $req_content
    my $resp = $self->post_request($part, $req_content);

    ### response: $resp->content
    my $info   = XMLin($resp->content, ForceArray => [ qw{ Config } ]);
    ### $info
    my $change = $self->change_info_class->new_from_raw_data($self, $info->{ChangeInfo});
    my $hz     = $self->hosted_zone_class->new_from_raw_data($self, $info->{HostedZone});
    # TODO delegtion info

    $self->_add_hosted_zone($hz->plain_id => $hz)
        if $self->has_fetched_hosted_zones;

    return wantarray ? ($hz, $change) : $hz;
}

=method copy_hosted_zone($hz)

Given a hosted zone object, create a new hosted zone and copy the contents of
the given zone to the new zone.

Returns the new hosted zone instance.

=cut

sub copy_hosted_zone {
    my ($self, $hz) = @_;

    #my $self = shift @_;
    #my ($hz) = validated_list

    confess '$hz is not a HostedZone instance!'
        unless blessed $hz && $hz->isa('Net::Amazon::R53::HostedZone');

    my $comment = 'Creating copy of zone ' . $hz->plain_id;

    my ($new_hz, $change) = $self->create_hosted_zone(
        name    => $hz->name,
        comment => $comment,
    );

    # if we haven't died yet, then the zone creation was queued/executed successfully

    my $copy_change = $new_hz->submit_resource_records_change_request(
        comment        => $comment,
        multi_batch_ok => 1,
        changes        => [
            map  { { action => 'CREATE', record => $_ } }
            grep { $_->type !~ /^(NS|SOA)$/             }
            $hz->resource_record_sets->flatten
        ],
    );

    return $new_hz;
}

=method delete_hosted_zone($hz_id | $hz)

Delete a hosted zone, by its id; both the plain id (e.g. C<ZIQB30DSWGWG6>)
or the full one Amazon returns (e.g. C</hostedzone/ZIQB30DSWGWG6>) are
acceptable ids.

We do not perform any validation.  If the zone doesn't exist, or is not
pristine (contains any non-Amazon record sets), or anything else goes
sideways, we'll just die.

=cut

sub delete_hosted_zone {
    my ($self, $hz_thing) = @_;

    my $path
        = blessed $hz_thing             ? $hz_thing->id
        : $hz_thing =~ m!^/hostedzone/! ? $hz_thing
        :                                 "/hostedzone/$hz_thing"
        ;

    my $resp = $self->delete_request($path, undef);

    # OK if we make it here w/o dying
    $self->_delete_hosted_zone($path->split(qr!/!)->pop)
        if $self->has_fetched_hosted_zones;

    # so here we do something a little different.  We use the ChangeInfo data
    # to construct our change object; this is the raw data that gets passed in
    # via new_from_raw_data(), but we also pass 'raw_data => $x', where $x is
    # the full set of returned data from Amazon.
    #
    # I could be easily convinced that some other approach is better.

    ### response: $resp->content
    my $info = XMLin($resp->content, KeepRoot => 1);
    return $self->change_info_class->new_from_raw_data(
        $self,
        $info->{DeleteHostedZoneResponse}->{ChangeInfo},
        raw_data => $info,
    );
}

=attr template_dir

The directory we expect to find our templates in.

=cut

has template_dir => (
    is      => 'lazy',
    isa     => Dir,
    builder => sub { dist_dir 'Net-Amazon-R53' },
);

has tt => (
    is        => 'lazy',
    isa_class => 'Template',
    builder   => sub { Template->new(DEBUG => 1, INCLUDE_PATH => shift->template_dir) },
);

# build a full url
sub _full_endpoint { shift->endpoint_base . shift }

=method request($method, $uri_part, $content)

Make a request to Route53.

=method get_request

Same as request(), but as a GET.

=method post_request

Same as request(), but as a POST.

=method delete_request

Same as request(), but as a DELETE.

=cut

sub get_request    { shift->request(GET    => @_) }
sub post_request   { shift->request(POST   => @_) }
sub delete_request { shift->request(DELETE => @_) }

sub request {
    my ($self, $method, $part, $content) = @_;

    # wtf lwp?
    $content ||= undef;

    my $req = HTTP::Request->new(
        $method,
        $self->_full_endpoint($part),
        [
            $self->signer->signed_headers,
            Host => 'route53.amazonaws.com',
        ],
        $content,
    );

    ### request: $req->as_string
    my $resp = $self->ua->request($req);

    ### request status: $resp->status_line
    confess "Fail! " . $resp->content
        if $resp->is_error;

    return $resp;
}

__PACKAGE__->meta->make_immutable;
!!42;
__END__

=for stopwords AWS DNS

=head1 SYNOPSIS

    use Net::Amazon::R53;

    my $r53 = Net::Amazon::R53->new(id => $aws_id, key => $aws_key);

    $r53
        ->get_hosted_zone('Z1345....')
        ->purge
        ->delete
        ;

    # ...etc.


=head1 DESCRIPTION

This is an interface to Amazon's Route53 DNS service.  It aims to be simple,
reliable, well tested, easily extensible, and capable of rescuing kittens from
volcanoes.

Well, maybe not that last part.

=head1 SEE ALSO

Amazon's docs and Route53 information, particularly:
http://docs.amazonwebservices.com/Route53/latest/DeveloperGuide/Welcome.html

L<Net::Amazon::Route53> is a prior implementation of an older Route53 API.

=cut
