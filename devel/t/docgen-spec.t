use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);

ok $spec, 'loaded';
is_deeply [ sort keys %{ $spec->paths } ], ['/things'], 'paths indexed';

my $thing = $spec->resolve_ref('#/components/schemas/Thing');
is $thing->{type}, 'object', 'ref resolution works';

is $spec->ref_name('#/components/schemas/Thing'), 'Thing', 'ref_name strips prefix';

# Refs in the loaded tree are NOT inlined.
my $body_schema =
    $spec->paths->{'/things'}{post}{requestBody}{content}{'application/json'}{schema};
is_deeply $body_schema, { '$ref' => '#/components/schemas/Thing' },
    'refs in path tree remain unresolved';

done_testing;
