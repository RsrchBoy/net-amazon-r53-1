package Net::Amazon::R53::Role::NewFromRawData;

# ABSTRACT: Constructs instances from just the returned raw_data

use Moose::Role;
use namespace::autoclean;
use MooseX::AttributeShortcuts;

use String::CamelCase 'decamelize';

# debugging...
#use Smart::Comments '###';

=attr raw_data <HashRef>

The raw, parsed data from Route53.  This attribute is required.

=cut

has raw_data => (is => 'ro', isa => 'HashRef', required => 1);

=method new_from_raw_data(<r53 instance>, <raw data hashref>)

This is an alternate constructor that creates an instance based on the raw
data returned by Route53; it's generally used internally.

=cut

sub new_from_raw_data {
    my ($class, $r53, $raw_data, @other_args) = @_;

    my %params = (raw_data => $raw_data);
    my $meta = $class->meta;

    for my $key (keys %$raw_data) {

        my $att_name = decamelize $key;
        $key =~ s/::/__/g;
        $params{$att_name} = $raw_data->{$key}
            if $meta->find_attribute_by_name($att_name);
    }

    ### %params
    return $class->new(r53 => $r53, %params, @other_args);
}

!!42;
