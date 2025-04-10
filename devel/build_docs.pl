#!/usr/bin/env perl

use 5.026;    # indented heredocs
use strict;
use warnings;
use experimental 'signatures';
use feature 'state';
use YAML::XS qw(LoadFile);
use Path::Tiny;
use JSON::PP;
use Carp  qw(croak);
use Clone qw(clone);
use Template;

# FIXME: switch from HEREDOCs to Templates

# --- Configuration ---
my $openapi_file    = path('share/openapi.yaml');
my $output_base_dir = path( 'lib', 'OpenAPI', 'Client', 'OpenAI', 'Path' );
my $main_index_file = $output_base_dir->sibling('Path.pod');

# --- Load and Preprocess OpenAPI Specification ---
my $openapi          = LoadFile($openapi_file);
my $resolved_openapi = preprocess_openapi( clone($openapi) );    # Clone to avoid modifying the original

die "Failed to parse OpenAPI specification (root element not found)" unless defined $resolved_openapi->{paths};

# --- Prepare Output Directory ---
$output_base_dir->mkpath( { parents => 1 } ) unless $output_base_dir->is_dir;

# --- Generate Individual Path POD Files ---
my %path_index_entries;

foreach my $path ( sort keys %{ $resolved_openapi->{paths} } ) {
    write_documentation_for_path( $resolved_openapi, $path, $output_base_dir, \%path_index_entries );
}

write_index( $main_index_file, \%path_index_entries, $resolved_openapi );

sub preprocess_openapi ($openapi) {
    # expand all references
    my $cloned = clone($openapi);

    # Don't delete components because they can refer to other components
    my $components = $cloned->{components};
    _recursively_find_references( $components, $cloned );
    return $cloned;
}

# walks through the OpenAPI spec and resolves all references.
sub _recursively_find_references ( $components, $resolved ) {

    # Cache the references to avoid resolving them multiple times. The script
    # was fast enough and memory efficient enough to not really need this, but
    # we cut memory usage by more than half and improved speed an order of
    # magnitude.
    state $cached = {};
    return unless ref $resolved;
    if ( 'ARRAY' eq ref $resolved ) {
        foreach my $item ( $resolved->@* ) {
            _recursively_find_references( $components, $item );
        }
    } elsif ( 'HASH' eq ref $resolved ) {
        if ( my $ref = $resolved->{'$ref'} ) {
            my $reference = $cached->{$ref} //= _resolve_reference( $components, $ref );
            $resolved->%* = ( %{$reference}, %{$resolved} );    # Merge reference into current hash
        }
    KEY: foreach my $key ( sort keys $resolved->%* ) {
            my $item = $resolved->{$key};
            _recursively_find_references( $components, $item );
        }
    }
}

sub _resolve_reference ( $components, $ref ) {
    my ( undef, undef, $type, $name ) = split '/', $ref;
    return $components->{$type}{$name} || croak "Could not resolve $ref";
}

sub get_example_from_schema ($schema) {
    if ( my $example = $schema->{'x-oaiMeta'}{example} ) {
        # FIXME: this is a nasty, nasty hack. x-oaiMeta is not part of the
        # OpenAPI spec, but it gives much better examples than trying to parse
        # manually. However, while those examples are easier to read and more
        # comprehensive, they're often not valid JSON. We return them as-is
        # and let the calling code handle it. Because this is a *recursive*
        # function, it's fragile, but so far, we only fine the x-oaiMeta key
        # at the top level, so we never hit recursion.
        return $example;
    }
    if ( defined $schema->{example} ) {
        return $schema->{example};
    } elsif ( defined $schema->{properties} ) {
        my %example;
    PROPERTY: foreach my $property_name ( keys %{ $schema->{properties} } ) {
            my $property_schema = $schema->{properties}->{$property_name};
            if ( defined $property_schema->{example} ) {
                $example{$property_name} = $property_schema->{example};
                next PROPERTY;
            }
            if (   defined $property_schema->{type}
                && $property_schema->{type} eq 'array'
                && defined $property_schema->{items} ) {
                $example{$property_name} = [ get_example_from_schema( $property_schema->{items} ) ];
            } elsif ( defined $property_schema->{type}
                && $property_schema->{type} eq 'object'
                && defined $property_schema->{properties} ) {
                $example{$property_name} = get_example_from_schema($property_schema);
            }
        }
        return \%example if %example;
    } elsif ( defined $schema->{type} && $schema->{type} eq 'array' && defined $schema->{items} ) {
        return [ get_example_from_schema( $schema->{items} ) ] if defined $schema->{items};
    }
    return undef;
}

sub write_documentation_for_path ( $resolved_openapi, $path, $output_base_dir, $path_index_entries ) {
    my $path_data              = $resolved_openapi->{paths}->{$path};
    my $sanitized_path_segment = $path;
    $sanitized_path_segment =~ s{^/+}{};
    $sanitized_path_segment =~ s{[/{}]}{-}g;
    $sanitized_path_segment =~ s{-+$}{};
    $sanitized_path_segment =~ s{--}{-}g;

    my $output_file = $output_base_dir->child("$sanitized_path_segment.pod");
    eval {
        $output_file->spew_utf8(<<~"POD");
          =encoding utf8
          
          =head1 NAME
          
          OpenAPI::Client::OpenAI::Path::$sanitized_path_segment - Documentation for the $path path.
          
          =head1 DESCRIPTION
          
          This document describes the API endpoint at C<$path>.

          See the C<examples/> directory in the distribution for examples of how to use this.
          
          POD

        if ( defined $path_data->{description} && $path_data->{description} ne '' ) {
            $output_file->append("$path_data->{description}\n\n");
        }

        my $tt       = Template->new( { TRIM => 1 } );
        my $template = _path_template();
        my $json     = JSON::PP->new->pretty->canonical;

        foreach my $method ( sort keys %{$path_data} ) {
            next if $method eq 'description' || $method eq 'parameters';

            my $method_data   = $path_data->{$method};
            my $method_upper  = uc $method;
            my $operation_id  = $method_data->{operationId};
            my %template_data = (
                path                   => $path,
                sanitized_path_segment => $sanitized_path_segment,
                path_data              => $path_data,
                operation_id           => $operation_id,
                method_data            => $method_data,
                year                   => (localtime)[5] + 1900,
            );

            $output_file->append("=head2 C<$method_upper $path>\n\n");

            if ( defined $method_data->{summary} && $method_data->{summary} ne '' ) {
                $output_file->append("$method_data->{summary}\n\n");
                $template_data{summary} = $method_data->{summary};
            }
            if ( defined $method_data->{description} && $method_data->{description} ne '' ) {
                $output_file->append("$method_data->{description}\n");
                $template_data{description} = $method_data->{description};
            }

            if ( defined $operation_id ) {
                $output_file->append(<<~"POD");
                  =head3 Operation ID
                  
                  C<$operation_id>

                      \$client->$operation_id( ... );
                  
                  POD
            }

            # Add parameter documentation
            if ( defined $method_data->{parameters} && @{ $method_data->{parameters} } ) {
                $output_file->append(<<~'POD');
                  =head3 Parameters
                  
                  =over 4
                  
                  POD

                foreach my $parameter ( @{ $method_data->{parameters} } ) {
                    my $name        = $parameter->{name};
                    my $in          = $parameter->{in};
                    my $description = $parameter->{description} || 'No description available.';
                    my $required    = $parameter->{required} ? '(Required)' : '(Optional)';

                    $output_file->append("=item * C<$name> (in $in) $required - $description\n");

                    if ( defined $parameter->{schema} && defined $parameter->{schema}->{type} ) {
                        $output_file->append("Type: C<$parameter->{schema}->{type}>\n\n");

                        if ( defined $parameter->{schema}->{enum} && @{ $parameter->{schema}->{enum} } ) {
                            $output_file->append("Possible values: C<@{ $parameter->{schema}->{enum} }>\n\n");
                        }
                        if ( defined $parameter->{schema}->{default} ) {
                            $output_file->append("Default: C<$parameter->{schema}->{default}>\n\n");
                        }
                    }
                }
                $output_file->append("\n=back\n\n");
            }

            # Add request body documentation with examples
            if ( defined $method_data->{requestBody} && defined $method_data->{requestBody}->{content} ) {
                $output_file->append("\n=head3 Request Body\n\n");
                foreach my $content_type ( sort keys %{ $method_data->{requestBody}->{content} } ) {
                    $output_file->append("=head3 Content Type: C<$content_type>\n\n");

                    if ( defined $method_data->{requestBody}->{content}->{$content_type}->{schema} ) {
                        my $schema = $method_data->{requestBody}->{content}->{$content_type}->{schema};

                        if ( defined( my $example = get_example_from_schema($schema) ) ) {
                            my $example_json = $json->encode($example);
                            # prepend each line with four spaces
                            $example_json =~ s/^/    /gm;
                            $output_file->append(<<~"POD");
                              
                              =head3 Example:
                              
                              $example_json
                              
                              POD
                        }
                    }
                }
            }

            # Add responses documentation with examples
            if ( defined $method_data->{responses} ) {
                $output_file->append("\n=head3 Responses\n\n");

                foreach my $status_code ( sort keys %{ $method_data->{responses} } ) {
                    my $response = $method_data->{responses}->{$status_code};
                    $output_file->append("=head3 Status Code: C<$status_code>\n\n");

                    if ( defined $response->{description} ) {
                        $output_file->append("$response->{description}\n\n");
                    }
                    if ( defined $response->{content} ) {
                        $output_file->append("Content Types:\n\n=over 4\n\n");
                        foreach my $content_type ( sort keys %{ $response->{content} } ) {
                            $output_file->append("=item * C<$content_type>\n");
                            if ( defined $response->{content}{$content_type}{schema} ) {
                                my $schema = $response->{content}{$content_type}{schema};

                                if ( defined( my $example = get_example_from_schema($schema) ) ) {
                                    my $example_json = ref $example ? $json->encode($example) : $example;
                                    # prepend each line with four spaces
                                    $example_json =~ s/^/    /gm;
                                    $response->{content}{$content_type}{schema}{example} = $example_json;
                                    $output_file->append(<<~"POD");
                                      
                                      Example:
                                      
                                      $example_json
                                      
                                      POD
                                }
                            }
                        }
                        $output_file->append("\n=back\n\n");
                    }
                }
            }
            # FIXME This will become default behavior
            if ( $template_data{operation_id} eq 'listAssistants' ) {
                my $output;
                $tt->process( \$template, \%template_data, \$output )
                    or die "Template processing failed: " . $tt->error;
                open my $fh, '>', 'assistants.pm' or die "Could not open assistants.pm': $!";
                warn $template_data{method_data}{responses}{200}{content}{'application/json'}{schema}{example};
                print $fh $output;
            }
        }
        $output_file->append(<<POD);

=head1 SEE ALSO

L<OpenAPI::Client::OpenAI::Path>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023-2025 by Nelson Ferraz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
POD
    };
    die "Error writing to '$output_file': $@" if $@;


    # Store information for the main index
    $path_index_entries->{$path} = {
        description => $path_data->{description} || 'No description available.',
        filename    => $sanitized_path_segment,
    };
}

sub write_index ( $main_index_file, $path_index_entries, $resolved_openapi ) {
    open my $index_fh, '>', $main_index_file or die "Could not open '$main_index_file': $!";

    print $index_fh "=encoding utf8\n\n";
    print $index_fh "=head1 NAME\n\n";
    print $index_fh "OpenAPI::Client::OpenAI::Path - Index of OpenAI API Paths\n\n";

    print $index_fh "=head1 DESCRIPTION\n\n";
    print $index_fh
        "This document provides an index of the available paths in the OpenAI API, along with the supported HTTP methods and their summaries.\n";
    print $index_fh "For detailed information about each path and its usage, please refer to the linked POD files.\n\n";

    print $index_fh "=head1 PATHS\n\n";

    foreach my $path ( sort keys %$path_index_entries ) {
        my $entry     = $path_index_entries->{$path};
        my $pod_link  = "L<OpenAPI::Client::OpenAI::Path::$entry->{filename}>";
        my $path_data = $resolved_openapi->{paths}->{$path};

        print $index_fh "=head2 C<$path>\n\n";

        if ( defined $path_data->{description} && $path_data->{description} ne '' ) {
            print $index_fh "$path_data->{description}\n\n";
        }

        print $index_fh "=over\n\n";
        foreach my $method ( sort keys %{$path_data} ) {
            next if $method eq 'description' || $method eq 'parameters';
            my $method_data  = $path_data->{$method};
            my $method_upper = uc $method;
            if ( defined $method_data->{summary} && $method_data->{summary} ne '' ) {
                print $index_fh "=item * C<$method_upper> - $method_data->{summary}\n\n";
            } else {
                print $index_fh "=item * $method_upper - No summary available.\n\n";
            }
        }
        print $index_fh "=back\n\n";

        print $index_fh "See $pod_link for more details.\n\n";

    }

    print $index_fh "=cut\n";

    my $current_year = (localtime)[5] + 1900;
    print $index_fh <<~"END";
    =head1 COPYRIGHT AND LICENSE

    Copyright (C) 2023-$current_year by Nelson Ferraz

    This library is free software; you can redistribute it and/or modify
    it under the same terms as Perl itself, either Perl version 5.14.0 or,
    at your option, any later version of Perl 5 you may have available.
    END

    close $index_fh;
}

sub _path_template () {
    return <<~'END_TEMPLATE';
    =encoding utf8
    
    =head1 NAME
    
    OpenAPI::Client::OpenAI::Path::[% sanitized_path_segment %] - Documentation for the [% path %] path.
    
    =head1 DESCRIPTION
    
    This document describes the API endpoint at C<[% path %]>.
    
    =head2 C<GET [% path %]>
    
    [% method_data.summary %]

    [% IF method_data.description %]
    [% method_data.description %]
    [% END %]
    
    =head3 Operation ID
    
    C<[% operation_id %]>
    
        $client->[% operation_id %]( ... );
    
    =head3 Parameters
    
    =over 4
    [% FOREACH parameter IN method_data.parameters %]
    =item * C<[% parameter.name %]> (in [% parameter.in %]) [% IF parameter.required %](Required)[% ELSE %](Optional)[% END %] - [% parameter.description %]
    Type: C<[% parameter.schema.type %]>

    [% IF parameter.schema.enum.size %]Allowed values: C<[% parameter.schema.enum.join(', ') %]>[% END %]
    
    [% IF parameter.schema.default %]Default: C<[% parameter.schema.default %]>[% END -%]
    
    [% END # END FOREACH %]
    =back
    
    [% IF method_data.responses %]
    =head3 Responses
    
    [% FOREACH status_code IN method_data.responses.keys.sort %]
    =head3 Status Code: C<[% status_code %]>
    
    [% method_data.responses.$status_code.description %]
    
    [% IF method_data.responses.$status_code.content %]
    Content Types:
    
    =over 4
    
    [% FOREACH content_type IN method_data.responses.$status_code.content.keys.sort %]
    =item * C<[% content_type %]>
    
    Example (See the L<OpenAI spec for more detail|https://github.com/openai/openai-openapi/blob/master/openapi.yaml>:
    
    [% method_data.responses.$status_code.content.$content_type.schema.example %]
    
    [% END # FOREACH content_type %]
    [% END # end if status_code.content%]
    [% END # end FOREACH status_code %]
    [% END # if method_data.resposnes %] 
    
    
    =back
    
    =head1 SEE ALSO
    
    L<OpenAPI::Client::OpenAI::Path>
    
    =head1 COPYRIGHT AND LICENSE
    
    Copyright (C) 2023-[% year %] by Nelson Ferraz
    
    This library is free software; you can redistribute it and/or modify
    it under the same terms as Perl itself, either Perl version 5.14.0 or,
    at your option, any later version of Perl 5 you may have available.
    
    =cut
    END_TEMPLATE
}
