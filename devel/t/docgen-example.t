use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Most;
use JSON::PP qw(decode_json);
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $ex = OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec );

# format_example: round-trips stringified JSON, encodes refs.
is $ex->format_example(undef), undef, 'undef in -> undef out';
is $ex->format_example('{"a":1}'),
    qq({\n   "a" : 1\n}\n), 'string JSON re-encoded canonically';
is $ex->format_example('not-json-at-all'), qq{"not-json-at-all"\n},
    'non-JSON string is treated as a quoted JSON string literal';
like $ex->format_example({ b => 2, a => 1 }),
    qr/"a"\s*:\s*1.*"b"\s*:\s*2/s, 'hash ref encoded canonically';

# Synthesis: walks properties of a schema (no example present), drilling into
# refs, with depth cap at 4 and visible truncation marker.
my $synth = $ex->synthesize_for( $spec->resolve_ref('#/components/schemas/Thing') );
is_deeply $synth, { name => 'string', size => 10 }, 'enum/default/scalar fallback';

# oneOf scoring: prefer the variant with its own example or with the most
# enum/default annotations.
my $oneof = {
    oneOf => [
        { type => 'string' },
        { type => 'string', enum => [ 'a', 'b' ] },
    ],
};
is $ex->synthesize_for($oneof), 'a', 'oneOf picks enum-bearing variant';

# resolve_example: priority chain per design §Examples.
# 1. schema.x-oaiMeta.example wins.
is_deeply
    $ex->resolve_example( {}, { 'x-oaiMeta' => { example => { hi => 1 } } } ),
    { hi => 1 },
    'resolve_example: schema.x-oaiMeta.example wins (priority 1)';

# 2. schema.example wins when no x-oaiMeta.
is_deeply
    $ex->resolve_example( {}, { example => { fallback => 1 } } ),
    { fallback => 1 },
    'resolve_example: schema.example used (priority 2)';

# 3. Method-level x-oaiMeta.examples[0].response when schema has neither.
is_deeply
    $ex->resolve_example(
        { 'x-oaiMeta' => { examples => [ { response => { from_method => 1 } } ] } },
        { type => 'object' },
    ),
    { from_method => 1 },
    'resolve_example: method-level x-oaiMeta wins over synthesis (priority 3)';

# 4. Synthesis fallback when none of the above match.
my $thing = $spec->resolve_ref('#/components/schemas/Thing');
is_deeply
    $ex->resolve_example( {}, $thing ),
    { name => 'string', size => 10 },
    'resolve_example: synthesizes from schema as last resort (priority 4)';

# Round-trip preserves valid JSON 'null' (regression: previously emitted
# a spurious carp and returned undef because !defined misread success).
is $ex->format_example('null'), "null\n", 'parseable JSON "null" round-trips';

# Walking a schema does not mutate the underlying spec tree (regression:
# previously autovivified x-oaiMeta => {} on every node).
my $live_thing = $spec->resolve_ref('#/components/schemas/Thing');
my %before = map { $_ => exists $live_thing->{$_} } keys %$live_thing;
$ex->synthesize_for($live_thing);
my %after = map { $_ => exists $live_thing->{$_} } keys %$live_thing;
ok !exists $live_thing->{'x-oaiMeta'}, 'no x-oaiMeta key autovivified on Thing';
ok !exists $live_thing->{properties}{name}{'x-oaiMeta'},
    'no x-oaiMeta autovivified on Thing.properties.name';

done_testing;
