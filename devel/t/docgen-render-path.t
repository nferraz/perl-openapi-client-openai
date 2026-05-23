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

# Regression: =head4 Request body must appear ONCE per operation,
# regardless of how many content-types are declared.
my $multi_ct_schema = {
    type => 'object',
    properties => {
        '/multi' => {
            post => {
                operationId => 'createMulti',
                requestBody => {
                    content => {
                        'application/json'    => { schema => { type => 'object', properties => { x => { type => 'string' } } } },
                        'multipart/form-data' => { schema => { type => 'object', properties => { y => { type => 'string' } } } },
                    },
                },
                responses => { '200' => { description => 'ok' } },
            },
        },
    },
};
# Splice a fake path into the spec just for this test.
$spec->paths->{'/multi'} = $multi_ct_schema->{properties}{'/multi'};
my $pod_multi = $renderer->render('/multi');
my $rb_count = () = $pod_multi =~ /=head4 Request body/g;
is $rb_count, 1, 'Request body heading appears exactly once across multiple content-types';
delete $spec->paths->{'/multi'};

# A component with no properties still gets a =head2 heading (with a fallback
# note) so that any L</Empty> links in the file remain valid.
my $empty_schema = { type => 'object' };   # no properties
my %scratch;
my @output;
my $rec_emit  = sub { push @output, @_ };
my $rec_blank = sub { push @output, '' };
$renderer->_emit_schemas_section( $rec_emit, $rec_blank, { Empty => $empty_schema } );
ok scalar( grep { /=head2 Empty/ } @output ),
    'property-less component still gets =head2 heading for link validity';

# Regression: a property-less request body suppresses the entire Request body section.
my $no_props_request = {
    operationId => 'createNada',
    requestBody => {
        content => {
            'application/json' => { schema => { type => 'object' } },   # no properties, no example
        },
    },
    responses => { '200' => { description => 'ok' } },
};
$spec->paths->{'/nada'} = { post => $no_props_request };
my $pod_nada = $renderer->render('/nada');
unlike $pod_nada, qr/=head4 Request body/,
    'no Request body heading when content has no properties and no example';
delete $spec->paths->{'/nada'};

done_testing;
