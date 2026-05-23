package OpenAPI::Client::OpenAI::DocGen::Render::Path;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

sub new ( $class, %args ) {
    return bless {
        spec    => $args{spec},
        example => $args{example},
        schema  => $args{schema},
    }, $class;
}

sub render ( $self, $path ) {
    my $path_data = $self->{spec}->paths->{$path};
    my $sanitized = _sanitize_path($path);
    my @lines;

    my $emit  = sub { push @lines, @_ };
    my $blank = sub { push @lines, '' };

    $emit->('=encoding utf8');
    $blank->();
    $emit->('=head1 NAME');
    $blank->();
    $emit->("OpenAPI::Client::OpenAI::Path::$sanitized - Documentation for the $path path.");
    $blank->();

    if ( my $desc = $path_data->{description} ) {
        $emit->('=head1 DESCRIPTION');
        $blank->();
        $emit->( md_to_pod($desc) );
        $blank->();
    }

    $emit->('=head1 OPERATIONS');
    $blank->();

    my %all_components;
    for my $method ( sort grep { !/^(?:description|parameters)$/ } keys %$path_data ) {
        my $method_data = $path_data->{$method};
        my $op_id       = $method_data->{operationId} // next;
        my $snake       = to_snake_case($op_id);
        my $verb        = uc $method;

        $emit->("=head2 $verb $path");
        $blank->();
        $emit->("=head3 $op_id");
        $blank->();
        $emit->("  \$client->$snake({");
        $emit->("      body => { ... },");
        $emit->("  });");
        $blank->();

        if ( my $summary = $method_data->{summary} ) {
            $emit->( md_to_pod($summary) );
            $blank->();
        }
        if ( my $desc = $method_data->{description} ) {
            $emit->( md_to_pod($desc) );
            $blank->();
        }

        $self->_emit_parameters( $emit, $blank, $method_data, \%all_components );
        $self->_emit_request_body( $emit, $blank, $method_data, \%all_components );
        $self->_emit_responses( $emit, $blank, $method_data, \%all_components );
    }

    $self->_emit_schemas_section( $emit, $blank, \%all_components );

    $emit->('=head1 SEE ALSO');
    $blank->();
    $emit->('L<OpenAPI::Client::OpenAI::Path>');
    $blank->();
    $emit->('=head1 COPYRIGHT AND LICENSE');
    $blank->();
    my $year = (localtime)[5] + 1900;
    $emit->("Copyright (C) 2023-$year by Nelson Ferraz");
    $blank->();
    $emit->('This library is free software; you can redistribute it and/or modify');
    $emit->('it under the same terms as Perl itself, either Perl version 5.14.0 or,');
    $emit->('at your option, any later version of Perl 5 you may have available.');
    $blank->();
    $emit->('=cut');

    return join( "\n", @lines ) . "\n";
}

sub _emit_parameters ( $self, $emit, $blank, $method_data, $components ) {
    my $params = $method_data->{parameters} or return;
    return unless @$params;

    $emit->('=head4 Path/query parameters');
    $blank->();
    $emit->('=over');
    $blank->();
    for my $p (@$params) {
        my $required = $p->{required} ? 'required' : 'optional';
        my $where    = $p->{in};
        my $type     = $p->{schema}{type} // 'string';
        my $desc     = $p->{description} ? ' - ' . md_to_pod( $p->{description} ) : '';
        $emit->("=item * C<$p->{name}> (in $where, $required, $type)$desc");
        $blank->();
        if ( $p->{schema}{enum} ) {
            $emit->( 'Allowed values: ' . join( ', ', @{ $p->{schema}{enum} } ) );
            $blank->();
        }
        if ( exists $p->{schema}{default} ) {
            $emit->("Default: $p->{schema}{default}");
            $blank->();
        }
    }
    $emit->('=back');
    $blank->();
}

sub _emit_request_body ( $self, $emit, $blank, $method_data, $components ) {
    my $body    = $method_data->{requestBody} or return;
    my $content = $body->{content}            or return;

    # Collect ct-specific content first so we can suppress the heading
    # entirely if every ct turned out to have nothing emit-worthy.
    my @ct_blocks;
    for my $ct ( sort keys %$content ) {
        my $schema = $content->{$ct}{schema} or next;
        my @prop_block;
        my $prop_emit  = sub { push @prop_block, @_ };
        my $prop_blank = sub { push @prop_block, '' };
        $self->_emit_property_block( $prop_emit, $prop_blank, $schema, $components );

        # Substance = has properties OR has a non-trivial example.
        # A synthesized example for a property-less object produces no useful
        # content (just "{}"), so we only emit an example when the schema has
        # an explicit example annotation or when properties give it substance.
        my $has_props = scalar grep { length $_ } @prop_block;
        my $has_explicit_example = (
            ( ref $schema eq 'HASH'
                && ( defined $schema->{example}
                    || ( ref $schema->{'x-oaiMeta'} eq 'HASH'
                        && defined $schema->{'x-oaiMeta'}{example} ) ) )
            || ( ref $method_data->{'x-oaiMeta'}{examples} eq 'ARRAY'
                && @{ $method_data->{'x-oaiMeta'}{examples} } )
        );
        my $should_emit_example = $has_props || $has_explicit_example;

        my @ex_block;
        if ($should_emit_example) {
            my $ex_emit  = sub { push @ex_block, @_ };
            my $ex_blank = sub { push @ex_block, '' };
            $self->_emit_example_block( $ex_emit, $ex_blank, $method_data, $schema );
        }
        my $has_example = scalar grep { length $_ } @ex_block;

        # If neither properties nor any example output, skip this ct entirely.
        next unless $has_props || $has_example;

        my @block;
        push @block, "Content-Type: $ct";
        push @block, '';
        push @block, @prop_block if $has_props;
        push @block, @ex_block   if $has_example;
        push @ct_blocks, \@block;
    }
    return unless @ct_blocks;

    $emit->('=head4 Request body');
    $blank->();
    for my $block (@ct_blocks) {
        $emit->(@$block);
    }
}

sub _emit_responses ( $self, $emit, $blank, $method_data, $components ) {
    my $responses = $method_data->{responses} or return;
    $emit->('=head4 Responses');
    $blank->();
    for my $code ( sort keys %$responses ) {
        my $r    = $responses->{$code};
        my $desc = $r->{description} // '';
        $emit->( 'B<' . $code . ' - ' . md_to_pod($desc) . '>' );
        $blank->();
        my $content = $r->{content} or next;
        for my $ct ( sort keys %$content ) {
            my $schema = $content->{$ct}{schema} or next;
            $emit->("Content-Type: $ct");
            $blank->();
            $self->_emit_property_block( $emit, $blank, $schema, $components );
            $self->_emit_example_block( $emit, $blank, $method_data, $schema );
        }
    }
}

sub _emit_property_block ( $self, $emit, $blank, $schema, $components ) {
    my $result = $self->{schema}->walk($schema);
    %$components = ( %$components, %{ $result->{referenced_components} } );

    my @props = @{ $result->{properties} };
    return unless @props;

    $emit->('Properties:');
    $blank->();
    $emit->('=over');
    $blank->();
    for my $p (@props) {
        my $required = $p->{required} ? ', required' : '';
        my $type     = $p->{type};
        my $desc     = $p->{description} ? ' - ' . md_to_pod( $p->{description} ) : '';
        if ( $p->{ref_target} ) {
            $emit->("=item * C<$p->{name}> ($p->{ref_target}$required)$desc");
            $blank->();
            $emit->("See L</$p->{ref_target}> below for shape.");
            $blank->();
            next;
        }
        $emit->("=item * C<$p->{name}> ($type$required)$desc");
        $blank->();
        if ( $p->{truncated} ) {
            $emit->(
                'Nested shape omitted at depth 4; see the full spec at '
                    . 'L<https://platform.openai.com/docs/api-reference>.'
            );
            $blank->();
            next;
        }
        if ( $p->{enum} ) {
            $emit->( 'Allowed values: ' . join( ', ', @{ $p->{enum} } ) );
            $blank->();
        }
        if ( exists $p->{default} ) {
            my $d = defined $p->{default} ? $p->{default} : 'null';
            $emit->("Default: $d");
            $blank->();
        }
    }
    $emit->('=back');
    $blank->();
}

sub _emit_example_block ( $self, $emit, $blank, $method_data, $schema ) {
    my $raw  = $self->{example}->resolve_example( $method_data, $schema );
    return unless defined $raw;
    my $json = $self->{example}->format_example($raw) // return;
    $emit->('Example:');
    $blank->();
    for my $line ( split /\n/, $json ) {
        $emit->("    $line");
    }
    $blank->();
}

sub _emit_schemas_section ( $self, $emit, $blank, $components ) {
    return unless %$components;

    # Collect component blocks; suppress any that produce no properties.
    my @component_blocks;
    for my $name ( sort keys %$components ) {
        my $schema = $components->{$name};
        my @block;
        my $blk_emit  = sub { push @block, @_ };
        my $blk_blank = sub { push @block, '' };
        my %scratch_components;
        $self->_emit_property_block( $blk_emit, $blk_blank, $schema, \%scratch_components );
        next unless @block;    # property-less component: skip entirely
        push @component_blocks, { name => $name, lines => \@block };
    }
    return unless @component_blocks;

    $emit->('=head1 SCHEMAS');
    $blank->();
    for my $entry (@component_blocks) {
        $emit->("=head2 $entry->{name}");
        $blank->();
        $emit->( @{ $entry->{lines} } );
    }
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
