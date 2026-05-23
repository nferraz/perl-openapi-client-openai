use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::PathIndex->new( spec => $spec );

my $pod = $renderer->render;

like $pod, qr/=head1 NAME/, 'NAME section';
like $pod, qr/=head2 \/things/, 'path listed';
like $pod, qr/POST.*create_thing/, 'POST shows snake_case method';
like $pod, qr/L<OpenAPI::Client::OpenAI::Path::things>/, 'link to per-path POD';

done_testing;
