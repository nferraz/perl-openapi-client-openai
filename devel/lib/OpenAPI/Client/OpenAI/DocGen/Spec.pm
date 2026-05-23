package OpenAPI::Client::OpenAI::DocGen::Spec;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use YAML::XS qw(LoadFile);
use Carp qw(croak);

sub load ( $class, $path ) {
    my $raw = LoadFile($path);
    croak "spec missing 'paths'" unless $raw->{paths};
    return bless { raw => $raw }, $class;
}

# Live reference to the underlying tree; do not mutate.
sub paths      ($self) { $self->{raw}{paths} }
sub components ($self) { $self->{raw}{components} || {} }
sub raw        ($self) { $self->{raw} }

# '#/components/schemas/Thing' -> 'Thing'
sub ref_name ( $self, $ref ) {
    my @parts = split '/', $ref;
    return $parts[-1];
}

# Resolve a JSON pointer like '#/components/schemas/Thing' against the spec.
# Does NOT inline anywhere -- callers consume the result directly; they don't
# splice it back into the tree.
sub resolve_ref ( $self, $ref ) {
    croak "expected ref starting with '#/', got '$ref'" unless $ref =~ m{^#/};
    my $pointer = substr( $ref, 2 );
    croak "empty pointer segment in '$ref'" if $pointer eq '' || $pointer =~ m{//};
    my @parts = split '/', $pointer;
    my $node = $self->{raw};
    for my $part (@parts) {
        $part =~ s{~1}{/}g;
        $part =~ s{~0}{~}g;
        croak "empty pointer segment in '$ref'" if $part eq '';
        $node = $node->{$part} // croak "cannot resolve $ref (no '$part')";
    }
    return $node;
}

1;
