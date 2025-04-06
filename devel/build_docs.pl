#!/usr/bin/env perl

use strict;
use warnings;
use experimental 'signatures';
use YAML::XS qw(LoadFile);    # Changed back to YAML::XS
use Path::Tiny;

# --- Configuration ---
my $openapi_file    = path('share/openapi.yaml');
my $output_base_dir = path( 'lib', 'OpenAPI', 'Client', 'OpenAI', 'Path' );
my $main_index_file = $output_base_dir->sibling('Path.pod');

# --- Load and Parse OpenAPI Specification ---
my $openapi;
eval { $openapi = LoadFile($openapi_file); };
die "Could not read or parse '$openapi_file': $@" if $@;

die "Failed to parse OpenAPI specification (root element not found)" unless defined $openapi->{paths};

# --- Prepare Output Directory ---
$output_base_dir->mkpath( { parents => 1 } ) unless $output_base_dir->is_dir;

# --- Generate Individual Path POD Files ---
my %path_index_entries;

foreach my $path ( sort keys %{ $openapi->{paths} } ) {
    write_documentation_for_path( $openapi, $path, $output_base_dir, \%path_index_entries );
}

write_index( $main_index_file, \%path_index_entries, $openapi );

sub write_documentation_for_path ( $openapi, $path, $output_base_dir, $path_index_entries ) {

    my $path_data              = $openapi->{paths}->{$path};
    my $sanitized_path_segment = $path;
    $sanitized_path_segment =~ s{^/+}{};        # Remove leading slashes
    $sanitized_path_segment =~ s{[/{}]}{-}g;    # Replace slashes and curly braces with hyphens
    $sanitized_path_segment =~ s{-+$}{};        # Remove trailing hyphens
    $sanitized_path_segment =~ s{--}{-}g;       # Collapse multiple hyphens

    my $output_file = $output_base_dir->child("$sanitized_path_segment.pod");

    eval {
        $output_file->spew_utf8(<<POD);
=head1 PATH: $path

POD
        if ( defined $path_data->{description} && $path_data->{description} ne '' ) {
            $output_file->append(<<POD);
$path_data->{description}

POD
        }

        foreach my $method ( sort keys %{$path_data} ) {
            next if $method eq 'description' || $method eq 'parameters';    # Skip non-method keys

            my $method_data  = $path_data->{$method};
            my $method_upper = uc $method;

            $output_file->append(<<POD);
=head2 $method_upper $path

POD
            if ( defined $method_data->{summary} && $method_data->{summary} ne '' ) {
                $output_file->append(<<POD);
$method_data->{summary}

POD
            }
            if ( defined $method_data->{description} && $method_data->{description} ne '' ) {
                $output_file->append(<<POD);
$method_data->{description}

POD
            }

            # You might want to add more details here, like parameters, request bodies, responses, etc.
        }
        $output_file->append("=cut\n");
    };
    die "Error writing to '$output_file': $@" if $@;

    # Store information for the main index
    $path_index_entries->{$path} = {
        description => $path_data->{description} || 'No description available.',
        filename    => $sanitized_path_segment,
    };
}

sub write_index ( $main_index_file, $path_index_entries, $openapi ) {

    open my $index_fh, '>', $main_index_file or die "Could not open '$main_index_file': $!";

    print $index_fh "=encoding utf8\n\n";
    print $index_fh "=head1 NAME\n\n";
    print $index_fh "OpenAPI::Client::OpenAI::Path - Documentation for OpenAI API Paths\n\n";

    print $index_fh "=head1 DESCRIPTION\n\n";
    print $index_fh
        "This document provides an index of the available paths in the OpenAI API, along with the supported HTTP methods and their summaries.\n";
    print $index_fh "For detailed information about each path and its usage, please refer to the linked POD files.\n\n";

    print $index_fh "=head1 PATHS\n\n";

    foreach my $path ( sort keys %$path_index_entries ) {
        my $entry     = $path_index_entries->{$path};
        my $pod_link  = "L<OpenAPI::Client::OpenAI::Path::$entry->{filename}>";
        my $path_data = $openapi->{paths}->{$path};

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
