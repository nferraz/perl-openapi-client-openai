#!/usr/bin/env perl

use v5.14.0;
use experimental 'signatures';
use autodie       qw(:all);
use Carp          qw(croak);
use Clone         qw(clone);
use Data::Dumper  qw(Dumper);
use Path::Tiny    qw(path);
use Text::Wrap    qw(wrap);
use YAML::XS      qw(LoadFile Dump);
use Markdown::Pod qw(markdown_to_pod);
use Feature::Compat::Try;
use Getopt::Long;
use Perl::Tidy;
use Template;

GetOptions( 'dump' => \my $dump, )
    or die "Invalid options";

my $yaml     = LoadFile('share/openapi.yaml');
my $resolved = preprocess_openapi($yaml);

if ($dump) {
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Deepcopy  = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Quotekeys = 0;
    print Dumper($resolved);
    exit;
}

my $paths = $resolved->{paths} or die "Could not find 'paths' in the OpenAPI spec";

my %methods;
foreach my $path ( sort keys $paths->%* ) {
    my $methods = $paths->{$path};
    my %pod;
    local $Text::Wrap::columns = 72;
    foreach my $http_verb ( keys $methods->%* ) {
        my $operation = $methods->{$http_verb};
        my $method_name = $operation->{operationId};
        my $summary     = $operation->{summary} || 'No summary provided';
        $summary = format_string($summary);
        my $parameters = $operation->{parameters} // [];
        foreach my $parameter ( $parameters->@* ) {
            $parameter->{description} = format_string( $parameter->{description} );
        }
        my $request_body;
        if ( $http_verb eq 'post' && ( $request_body = $operation->{requestBody} ) ) {
            $request_body = Dump( $request_body->{content} );
            # use regex to indent the content by four spaces
            $request_body =~ s/^/    /gm;
        }
        $methods{$method_name} = {
            summary      => $summary,
            parameters   => $operation->{parameters},
            request_body => $request_body,
        };
    }
}

my $method_pod_file = 'lib/OpenAPI/Client/OpenAI/Methods.pod';
write_method_pod( $method_pod_file, \%methods );
my $schema_pod_file = 'lib/OpenAPI/Client/OpenAI/Schema.pod';
my $yaml = Dump($resolved);
$yaml =~ s/^/    /gm;
write_schema_pod( $schema_pod_file, $yaml );
say "Documentation written to $method_pod_file. Schema written to $schema_pod_file";

sub write_method_pod ( $filename, $methods ) {
    my $tt = Template->new;
    $tt->process( pod_method_template(), { methods => $methods }, \my $pod ) or die $tt->error;
    open my $fh, '>', $filename;
    print {$fh} $pod;
}

sub write_schema_pod ( $filename, $schema ) {
    my $tt = Template->new;
    $tt->process( pod_schema_template(), { schema => $schema }, \my $pod ) or die $tt->error;
    open my $fh, '>', $filename;
    print {$fh} $pod;
}

sub pod_schema_template () {
	return \<<'TEMPLATE';
=head1 NAME

OpenAPI::Client::OpenAI::Schema - OpenAI API client Schema

=head1 DESCRIPTION

This module contains the schema for the OpenAI API client. To aid in
comprehension, the schema has all references resolved. This makes this schema
much larger than the original OpenAPI schema.

=head1 SCHEMA

[% schema %]

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023-2024 by Nelson Ferraz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.0 or,
at your option, any later version of Perl 5 you may have available.
TEMPLATE
}

sub pod_method_template () {
    return \<<'TEMPLATE';
=head1 NAME

OpenAPI::Client::OpenAI::Methods - Methods for OpenAI API

=head1 METHODS

[% FOREACH method IN methods.keys.sort %]
[%- summary = methods.$method.summary -%]
[%- parameters = methods.$method.parameters -%]
[%- request_body = methods.$method.request_body -%]

[%- IF summary %]
=head2 [% method %]

[% methods.$method.summary %]
[% IF parameters %]
=head3 Parameters

[% FOREACH parameter IN parameters %]
=head4 [% parameter.name %]

[% parameter.description -%]

=over 4

=item * Type:     [% parameter.schema.type %]

=item * In:       [% parameter.in %]

=item * Required: [% IF parameter.required %]True[% ELSE %]False[% END %]

=item * Default:  [% parameter.schema.default || 'N/A' %]

=item * Example:  [% parameter.schema.example || 'N/A' %]

=item * Enum:     [% parameter.schema.enum.join(', ') || 'N/A' %]

=back

[% END %]
[% ELSE %]
This method does not take any path or URL parameters.
[% END %]
[% END %]
[%- IF request_body %]
=head3 Request Body

The request body is complicated. See L<OpenAPI::Client::OpenAI::Schema> for details.

[%-END -%]
[% END -%]

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023-2024 by Nelson Ferraz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
TEMPLATE

}

sub format_string ($string) {
    return unless defined $string;
    # their openapi.yaml on github uses relative links to the docs, even
    # though the docs are on a different domain
    my $root_url = 'https://platform.openai.com';
    $string =~ s{\((/docs[^)]+)\)}{($root_url$1)}g;
    my $m2p = Markdown::Pod->new;
    return wrap( '', '', $m2p->markdown_to_pod( markdown => $string ) );
}

sub preprocess_openapi ($openapi) {
    my $cloned = clone($openapi);

    # Don't delete components because they can refer to other components
    my $components = $cloned->{components};
    _recursively_find_references( $components, $cloned );
    return $cloned;
}

# walks through the OpenAPI spec and resolves all references. If there are
# descriptions, they are converted from Markdown to POD.
sub _recursively_find_references ( $components, $resolved ) {
    return unless ref $resolved;
    if ( 'ARRAY' eq ref $resolved ) {
        foreach my $item ( $resolved->@* ) {
            _recursively_find_references( $components, $item );
        }
    } elsif ( 'HASH' eq ref $resolved ) {
        if ( exists $resolved->{'$ref'} ) {
            my $reference = _resolve_reference( $components, delete $resolved->{'$ref'} );
            $resolved->%* = ( $reference->%*, $resolved->%* );
        }
    KEY: foreach my $key ( sort keys $resolved->%* ) {
            my $item = $resolved->{$key};
            if ( 'x-oaiMeta' eq $key ) {
                delete $resolved->{$key};
                next KEY;
            }
            _recursively_find_references( $components, $item );
        }
    }
}

sub _resolve_reference ( $components, $ref ) {
    my ( undef, undef, $type, $name ) = split '/', $ref;
    return $components->{$type}{$name} || croak "Could not resolve $ref";
}

sub protect_code ( $filename, $existing_code, $protected_code, $overwrite ) {
    try {
        return rewrite_code(
            type           => 'Perl',
            name           => $filename,
            existing_code  => $existing_code,
            protected_code => $protected_code,
            overwrite      => $overwrite,
        );
    } catch ($error) {
        Carp::confess("Could not process changes to $filename: $error");
    }
}

sub tidy_code ($code) {
    my ( $stderr, $tidied );

    my $perltidyrc = path('.perltidyrc')->absolute;
    open my $fh, '<', $perltidyrc;
    $perltidyrc = do { local $/; <$fh> };
    close $fh;

    local @ARGV = ();
    Perl::Tidy::perltidy(
        source      => \$code,
        destination => \$tidied,
        stderr      => \$stderr,
        perltidyrc  => \$perltidyrc,
    ) and die "Perl::Tidy error: $stderr";

    return $tidied;
}

1;

__END__

