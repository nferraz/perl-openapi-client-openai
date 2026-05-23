package OpenAPI::Client::OpenAI::DocGen::Schema;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';

sub new ( $class, %args ) {
    return bless {
        spec      => $args{spec},
        max_depth => $args{max_depth} // 4,
    }, $class;
}

# Walk a schema (request body, response body, parameter schema).
# Returns { properties => [@records], referenced_components => { Name => $schema } }
sub walk ( $self, $schema ) {
    my %state = (
        depth                 => 0,
        active_refs           => {},
        referenced_components => {},
    );
    my @props = $self->_walk_object( $schema, \%state );
    return {
        properties            => \@props,
        referenced_components => $state{referenced_components},
    };
}

sub _walk_object ( $self, $schema, $state ) {
    return () unless ref $schema eq 'HASH';

    if ( my $ref = $schema->{'$ref'} ) {
        my $name = $self->{spec}->ref_name($ref);
        $state->{referenced_components}{$name} //= $self->{spec}->resolve_ref($ref);
        return ();   # caller wraps this as a single ref_target record
    }

    my $props = $schema->{properties} or return ();
    my %required = map { $_ => 1 } @{ $schema->{required} // [] };

    my @records;
    for my $name ( sort keys %$props ) {
        push @records, $self->_record_for( $name, $props->{$name}, $required{$name}, $state );
    }
    return @records;
}

sub _record_for ( $self, $name, $schema, $is_required, $state ) {
    my %rec = (
        name        => $name,
        required    => $is_required ? 1 : 0,
        description => $schema->{description},
    );

    if ( my $ref = $schema->{'$ref'} ) {
        my $rname = $self->{spec}->ref_name($ref);
        $state->{referenced_components}{$rname} //= $self->{spec}->resolve_ref($ref);
        $rec{ref_target} = $rname;
        $rec{type}       = $rname;   # display purposes
        return \%rec;
    }

    $rec{type}    = $schema->{type}    // _infer_type($schema);
    $rec{enum}    = $schema->{enum}    if $schema->{enum};
    $rec{default} = $schema->{default} if exists $schema->{default};

    # Inline anonymous object: recurse up to max_depth, then flag for truncation.
    if ( ( $schema->{type} // '' ) eq 'object' && $schema->{properties} ) {
        if ( $state->{depth} < $self->{max_depth} ) {
            local $state->{depth} = $state->{depth} + 1;
            $rec{children} = [ $self->_walk_object( $schema, $state ) ];
        }
        else {
            $rec{truncated} = 1;
        }
    } elsif ( ( $schema->{type} // '' ) eq 'array' && $schema->{items} ) {
        my $items = $schema->{items};
        if ( my $ref = $items->{'$ref'} ) {
            my $rname = $self->{spec}->ref_name($ref);
            $state->{referenced_components}{$rname} //= $self->{spec}->resolve_ref($ref);
            $rec{items_ref} = $rname;
            $rec{type}      = "array of $rname";
        } else {
            $rec{type} = 'array of ' . ( $items->{type} // 'object' );
        }
    }

    return \%rec;
}

sub _infer_type ($schema) {
    return 'oneOf'   if $schema->{oneOf};
    return 'anyOf'   if $schema->{anyOf};
    return 'allOf'   if $schema->{allOf};
    return 'unknown';
}

1;
