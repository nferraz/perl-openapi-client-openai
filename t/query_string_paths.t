use strict;
use warnings;
use Test::Most;

BEGIN { $ENV{OPENAI_API_KEY} //= 'test-key' }

# A path key with an embedded query string (e.g. '/responses?beta=true') is not
# a path template. OpenAPI::Client splits on '/' and pushes each segment onto a
# Mojo::Path, which percent-encodes the '?', so any generated method would
# request /thing%3Fbeta=true and always 404. Such paths must not reach the
# client at all -- neither as a method nor as a snake_case alias.

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use OpenAPI::Client::OpenAI;

my $fixture = catfile( dirname(__FILE__), 'fixtures', 'query-string-spec.yaml' );

my $client = OpenAPI::Client::OpenAI->new($fixture);

ok $client->can('createThing'), 'routable path still generates its method';
ok !$client->can('beta_createThing'),
    'query-string path generates no method';
ok !OpenAPI::Client::OpenAI->can('beta_create_thing'),
    'query-string path generates no snake_case alias';

my $ids = OpenAPI::Client::OpenAI::_operation_ids_from_spec_file($fixture);
is_deeply $ids, ['createThing'],
    'operationId harvest skips query-string paths';

# Guard the mechanism itself, so this test still fails if someone "fixes" the
# filter by special-casing the string 'beta'.
my $url = Mojo::URL->new('https://example.invalid/v1');
push @{ $url->path }, grep { length } split '/', '/thing?beta=true';
like "$url", qr/%3F/,
    'Mojo percent-encodes a query string embedded in a path segment';

done_testing;
