use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Schema;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $walker = OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec );

my $result = $walker->walk( $spec->resolve_ref('#/components/schemas/Thing') );

# Returns { properties => [...], referenced_components => { Name => $schema } }
isa_ok $result, 'HASH';
ok ref $result->{properties} eq 'ARRAY';

my %by_name = map { $_->{name} => $_ } @{ $result->{properties} };
is $by_name{name}{type},     'string',  'name property type';
is $by_name{size}{type},     'integer', 'size property type';
is $by_name{size}{default},  10,        'size default';

# A schema with a $ref to a named component records the component for the
# SCHEMAS section but does not recurse inline.
my $wrapper = { type => 'object', properties => { thing => { '$ref' => '#/components/schemas/Thing' } } };
my $r2 = $walker->walk($wrapper);
ok exists $r2->{referenced_components}{Thing}, 'ref to named component noted';
my ($thing_prop) = grep { $_->{name} eq 'thing' } @{ $r2->{properties} };
is $thing_prop->{ref_target}, 'Thing', 'inline property notes the ref target';

# Truncation: nested anonymous objects beyond max_depth get a flag.
# Build an object nested 5 levels deep.
my $deep = { type => 'object', properties => {} };
my $cur  = $deep;
for my $level ( 1 .. 5 ) {
    $cur->{properties}{"l$level"} = { type => 'object', properties => {} };
    $cur = $cur->{properties}{"l$level"};
}
$cur->{properties}{leaf} = { type => 'string' };

my $r3 = $walker->walk($deep);

sub find_truncated {
    my ($props) = @_;
    for my $p (@$props) {
        return $p if $p->{truncated};
        if ( $p->{children} ) {
            my $hit = find_truncated( $p->{children} );
            return $hit if $hit;
        }
    }
    return undef;
}

my $trunc = find_truncated( $r3->{properties} );
ok defined $trunc, 'truncated property flagged at depth 4';
is $trunc->{type}, 'object', 'truncated property keeps its type';

done_testing;
