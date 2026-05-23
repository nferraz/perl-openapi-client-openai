package OpenAPI::Client::OpenAI::DocGen::Example;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use JSON::PP;
use Carp qw(carp);

my $JSON = JSON::PP->new->canonical->pretty;

sub new ( $class, %args ) {
    return bless {
        spec      => $args{spec},
        max_depth => $args{max_depth} // 4,
    }, $class;
}

# Normalize a raw example into canonical pretty JSON text.
# Accepts a Perl structure, a stringified JSON document, or undef.
# Returns undef when given undef or an unparseable string.
sub format_example ( $self, $raw ) {
    return undef unless defined $raw;
    if ( !ref $raw ) {
        my $decoded = eval { $JSON->decode($raw) };
        if ( !defined $decoded ) {
            carp "format_example: input is neither a ref nor parseable JSON; omitting";
            return undef;
        }
        return $JSON->encode($decoded);
    }
    return $JSON->encode($raw);
}

# Resolve an example for a (method_data, schema) pair per design §Examples:
#   1. schema.x-oaiMeta.example
#   2. schema.example
#   3. method-level x-oaiMeta.examples[0].response
#   4. synthesize from schema
# Always returns either the raw value (for format_example to encode) or undef
# if nothing usable was found. Callers should pass {} as $method_data when no
# method-level context applies (e.g. nested schemas).
sub resolve_example ( $self, $method_data, $schema ) {
    if ( ref $schema eq 'HASH' ) {
        if ( defined( my $ex = $schema->{'x-oaiMeta'}{example} ) ) { return $ex }
        if ( defined( my $ex = $schema->{example} ) )              { return $ex }
    }
    if ( ref $method_data eq 'HASH'
        && ref $method_data->{'x-oaiMeta'}{examples} eq 'ARRAY'
        && @{ $method_data->{'x-oaiMeta'}{examples} } )
    {
        my $resp = $method_data->{'x-oaiMeta'}{examples}[0]{response};
        return $resp if defined $resp;
    }
    return $self->synthesize_for($schema);
}

# Returns a Perl scalar/structure suitable for $JSON->encode. Returns undef
# only when the schema offers no usable signal at all.
sub synthesize_for ( $self, $schema ) {
    my %state = ( depth => 0, active_refs => {} );
    return $self->_walk( $schema, \%state );
}

sub _walk ( $self, $schema, $state ) {
    return '...' unless defined $schema && ref $schema eq 'HASH';

    # 1. Schema-level x-oaiMeta example wins.
    if ( my $ex = $schema->{'x-oaiMeta'}{example} // $schema->{example} ) {
        return $ex;
    }

    # 2. Refs: cycle-detect by name, reset depth on cross.
    if ( my $ref = $schema->{'$ref'} ) {
        my $name = $self->{spec}->ref_name($ref);
        return { '...' => '...' } if $state->{active_refs}{$name};
        local $state->{active_refs}{$name} = 1;
        local $state->{depth} = 0;   # depth resets on crossing a named component
        return $self->_walk( $self->{spec}->resolve_ref($ref), $state );
    }

    return { '...' => '...' } if $state->{depth} >= $self->{max_depth};

    # 3. Combinators.
    if ( $schema->{allOf} ) {
        my %merged;
        for my $variant ( @{ $schema->{allOf} } ) {
            my $v = $variant->{'$ref'} ? $self->{spec}->resolve_ref($variant->{'$ref'}) : $variant;
            if ( ref $v eq 'HASH' && $v->{properties} ) {
                %merged = ( %merged, %{ $v->{properties} } );
            }
        }
        return $self->_walk( { type => 'object', properties => \%merged }, $state );
    }
    if ( my $variants = $schema->{oneOf} // $schema->{anyOf} ) {
        return $self->_walk( $self->_pick_variant($variants), $state );
    }

    # 4. Scalars: default → first enum → type stub.
    if ( exists $schema->{default} ) { return $schema->{default} }
    if ( $schema->{enum} && @{ $schema->{enum} } ) { return $schema->{enum}[0] }

    my $type = $schema->{type} // '';
    if ( $type eq 'object' || $schema->{properties} ) {
        my %out;
        local $state->{depth} = $state->{depth} + 1;
        for my $prop ( keys %{ $schema->{properties} // {} } ) {
            $out{$prop} = $self->_walk( $schema->{properties}{$prop}, $state );
        }
        return \%out;
    }
    if ( $type eq 'array' ) {
        my $items = $schema->{items} or return [];
        local $state->{depth} = $state->{depth} + 1;
        return [ $self->_walk( $items, $state ) ];
    }

    # Scalar type stubs.
    return 'string'  if $type eq 'string';
    return 0         if $type eq 'integer' || $type eq 'number';
    return JSON::PP::false if $type eq 'boolean';
    return undef;
}

# Score variants per design §Examples:
#   1. own example/x-oaiMeta.example
#   2. most enum/default annotations
#   3. most properties
#   4. first
sub _pick_variant ( $self, $variants ) {
    my $score = sub ( $v ) {
        my $s = 0;
        my $has_example = exists $v->{example}
            || ( ref $v->{'x-oaiMeta'} eq 'HASH' && exists $v->{'x-oaiMeta'}{example} );
        $s += 1000 if $has_example;
        $s += 10   if exists $v->{enum};
        $s += 10   if exists $v->{default};
        $s +=  1 * keys %{ $v->{properties} // {} };
        return $s;
    };
    my ($best) = sort { $score->($b) <=> $score->($a) } @$variants;
    return $best // $variants->[0];
}

1;
