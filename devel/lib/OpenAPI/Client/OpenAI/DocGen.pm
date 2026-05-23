package OpenAPI::Client::OpenAI::DocGen;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use Path::Tiny;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;
use OpenAPI::Client::OpenAI::DocGen::Schema;
use OpenAPI::Client::OpenAI::DocGen::Render::Path;
use OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;
use OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex;

sub new ( $class, %args ) {
    return bless {
        spec_file  => $args{spec_file},
        output_dir => path( $args{output_dir} ),
    }, $class;
}

sub run ($self) {
    my $spec     = OpenAPI::Client::OpenAI::DocGen::Spec->load( $self->{spec_file} );
    my $example  = OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec );
    my $schema   = OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec );
    my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::Path->new(
        spec    => $spec,
        example => $example,
        schema  => $schema,
    );

    my $base = $self->{output_dir}->child('lib/OpenAPI/Client/OpenAI');
    $base->child('Path')->mkpath;

    for my $path ( sort keys %{ $spec->paths } ) {
        my $sanitized = _sanitize_path($path);
        my $pod = $renderer->render($path);
        $base->child("Path/$sanitized.pod")->spew_utf8($pod);
    }

    my $path_index = OpenAPI::Client::OpenAI::DocGen::Render::PathIndex->new( spec => $spec );
    $base->child('Path.pod')->spew_utf8( $path_index->render );

    my $method_index = OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex->new( spec => $spec );
    $base->child('Methods.pod')->spew_utf8( $method_index->render );
}

sub _sanitize_path ($path) {
    my $s = $path;
    $s =~ s{^/+}{};
    $s =~ s{[/{}]}{-}g;
    $s =~ s{-+$}{};
    $s =~ s{--+}{-}g;
    return $s;
}

1;
