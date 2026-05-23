use strict;
use warnings;
use Test::Most;

BEGIN { $ENV{OPENAI_API_KEY} //= 'test-key' }

# Phase 1.2 will add a second block that loads this fixture through
# OpenAPI::Client::OpenAI->new(spec_file => ...) and asserts the actual
# croak. This commit covers the underlying helper against the fixture.
use OpenAPI::Client::OpenAI::Naming qw(detect_collisions);
use YAML::XS qw(LoadFile);

my $spec = LoadFile('t/fixtures/colliding-spec.yaml');
my @op_ids;
for my $path ( values %{ $spec->{paths} } ) {
    for my $method ( values %$path ) {
        next unless ref $method eq 'HASH' && $method->{operationId};
        push @op_ids, $method->{operationId};
    }
}

my $collisions = detect_collisions( \@op_ids );
ok exists $collisions->{create_thing}, 'create_thing collision detected';
is_deeply $collisions->{create_thing},
    [ sort qw(createThing create_thing) ],
    'both operationIds named in the collision entry';

done_testing;
