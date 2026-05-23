use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $r = OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex->new( spec => $spec );
my $pod = $r->render;

like $pod, qr/=head2 create_thing/, 'snake_case method head';
like $pod, qr/POST \/things/, 'verb + path';
like $pod, qr/operationId: createThing/, 'original operationId noted';
like $pod, qr/L<OpenAPI::Client::OpenAI::Path::things>/, 'link to per-path POD';

done_testing;
