package OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

sub new ( $class, %args ) { bless { spec => $args{spec} }, $class }

sub render ($self) {
    my @entries;
    my $paths = $self->{spec}->paths;
    for my $path ( sort keys %$paths ) {
        my $pdata = $paths->{$path};
        for my $method ( sort grep { !/^(?:description|parameters)$/ } keys %$pdata ) {
            my $md = $pdata->{$method};
            my $op = $md->{operationId} // next;
            push @entries, {
                snake     => to_snake_case($op),
                op        => $op,
                verb      => uc $method,
                path      => $path,
                sanitized => _sanitize_path($path),
                summary   => $md->{summary} // '',
            };
        }
    }

    my @lines;
    push @lines, '=encoding utf8', '';
    push @lines, '=head1 NAME', '';
    push @lines, 'OpenAPI::Client::OpenAI::Methods - Index of API methods (snake_case)', '';
    push @lines, '=head1 METHODS', '';

    for my $e ( sort { $a->{snake} cmp $b->{snake} } @entries ) {
        push @lines, "=head2 $e->{snake}", '';
        push @lines, "$e->{verb} $e->{path}", '';
        push @lines, "operationId: $e->{op}", '';
        if ( length $e->{summary} ) {
            push @lines, md_to_pod( $e->{summary} ), '';
        }
        push @lines, "See L<OpenAPI::Client::OpenAI::Path::$e->{sanitized}>.", '';
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
