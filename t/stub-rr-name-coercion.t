use strict;
use warnings;

use Test::More;

use aliased 'Net::Amazon::R53::ResourceRecordSet::Stub';

my $rr = Stub->new(name => 'foo.com', type => 'A');
is $rr->name, 'foo.com.', 'name coerced correctly';

$rr = Stub->new(name => 'foo.com.', type => 'A');
is $rr->name, 'foo.com.', 'name correct';

done_testing;
