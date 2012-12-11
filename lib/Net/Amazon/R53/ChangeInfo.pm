package Net::Amazon::R53::ChangeInfo;

# ABSTRACT: Contains change info for aidempotent Route53 requests

use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints 'enum';
use MooseX::AttributeShortcuts;
use MooseX::StrictConstructor;

use constant ValidStatuses => enum [ qw{ PENDING INSYNC } ];

with 'MooseX::Traitor';
with
    'Net::Amazon::R53::Role::NewFromRawData',
    'Net::Amazon::R53::Role::ParentR53',
    ;

=reqatt id

The change id as returned from Route53.

=reqatt status

The status as of last check; will be either 'PENDING' or 'INSYNC'.

=reqatt submitted_at

The date/time the request this change identified was submitted to Route53.

=cut

has id           => (is => 'ro',  isa => 'Str',         required => 1);
has status       => (is => 'rwp', isa => ValidStatuses, required => 1);
has submitted_at => (is => 'ro',  isa => 'Str',         required => 1);

=method is_complete

Returns true if the request is complete (that is, the request has been
accepted by Route53 and propagated through the Route53 infrastructure).

Note that this is the same as status being 'INSYNC'.

=cut

sub is_complete { shift->status eq 'INSYNC' }

__PACKAGE__->meta->make_immutable;
!!42;
__END__

=for stopwords aidempotent PENDING INSYNC

=head1 DESCRIPTION

This class represents a information corresponding to a change submitted to
Route53.  You will probably never need to create one of these yourself.

=cut
