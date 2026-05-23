use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use Pod::Checker;

use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;
use OpenAPI::Client::OpenAI::DocGen::Schema;
use OpenAPI::Client::OpenAI::DocGen::Render::Path;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::Path->new(
    spec    => $spec,
    example => OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec ),
    schema  => OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec ),
);

my $pod = $renderer->render('/things');

# Structural checks.
like $pod, qr/^=encoding utf8/m, 'encoding';
like $pod, qr/=head1 NAME/,      'NAME section';
like $pod, qr/=head2 POST \/things/, 'method header';
like $pod, qr/=head3 createThing/, 'operationId head3';
like $pod, qr/\$client->create_thing/, 'snake_case in synopsis';
like $pod, qr/=head1 SCHEMAS/, 'SCHEMAS section (Thing is referenced)';
like $pod, qr/=head2 Thing/, 'Thing component documented under SCHEMAS';

# No empty =over/=back blocks.
unlike $pod, qr/=over\s*\n\s*=back/, 'no empty over/back';

# podchecker: zero errors on this synthetic spec.
my $checker = Pod::Checker->new( -warnings => 1, -quiet => 1 );
open my $sink, '>', \my $output_buf or die "open scalar: $!";
my $tmp = "/tmp/render-path-out-$$.pod";
open my $tmp_fh, '>', $tmp or die "open $tmp: $!";
print $tmp_fh $pod;
close $tmp_fh;
$checker->parse_from_file( $tmp, $sink );
unlink $tmp;
is $checker->num_errors, 0, 'no podchecker errors';

done_testing;
