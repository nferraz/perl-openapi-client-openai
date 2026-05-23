package OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

sub new ( $class, %args ) { bless { spec => $args{spec} }, $class }

sub render ($self) {
    my @lines;
    push @lines, '=encoding utf8', '';
    push @lines, '=head1 NAME', '';
    push @lines, 'OpenAPI::Client::OpenAI::Path - Index of OpenAI API Paths', '';
    push @lines, '=head1 DESCRIPTION', '';
    push @lines, 'Index of paths in the OpenAI API; each links to its per-path documentation.', '';
    push @lines, '=head1 PATHS', '';

    my $paths = $self->{spec}->paths;
    for my $path ( sort keys %$paths ) {
        my $pdata = $paths->{$path};
        my $sanitized = _sanitize_path($path);

        push @lines, "=head2 $path", '';
        if ( my $desc = $pdata->{description} ) {
            push @lines, md_to_pod($desc), '';
        }
        push @lines, '=over', '';
        for my $method ( sort grep { !/^(?:description|parameters)$/ } keys %$pdata ) {
            my $md     = $pdata->{$method};
            my $verb   = uc $method;
            my $op     = $md->{operationId} // next;
            my $snake  = to_snake_case($op);
            my $summary = $md->{summary} // '';
            push @lines, "=item * C<$verb> $snake - " . md_to_pod($summary), '';
        }
        push @lines, '=back', '';
        push @lines, "See L<OpenAPI::Client::OpenAI::Path::$sanitized>.", '';
    }

    push @lines, _copyright();
    return join( "\n", @lines ) . "\n";
}

sub _sanitize_path ($path) {
    my $s = $path;
    $s =~ s{^/+}{};
    $s =~ s{[/{}]}{-}g;
    $s =~ s{-+$}{};
    $s =~ s{--+}{-}g;
    return $s;
}

sub _copyright {
    my $year = (localtime)[5] + 1900;
    return (
        '=head1 COPYRIGHT AND LICENSE',
        '',
        "Copyright (C) 2023-$year by Nelson Ferraz",
        '',
        'This library is free software; you can redistribute it and/or modify',
        'it under the same terms as Perl itself, either Perl version 5.14.0 or,',
        'at your option, any later version of Perl 5 you may have available.',
        '',
        '=cut',
    );
}

1;
