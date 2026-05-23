#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

unless ( $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Author tests not required for installation" );
}

# Ensure a recent version of Test::Pod::Coverage
my $min_tpc = 1.08;
eval "use Test::Pod::Coverage $min_tpc";
plan skip_all => "Test::Pod::Coverage $min_tpc required for testing POD coverage"
    if $@;

# Test::Pod::Coverage doesn't require a minimum Pod::Coverage version,
# but older versions don't recognize some common documentation styles
my $min_pc = 0.18;
eval "use Pod::Coverage $min_pc";
plan skip_all => "Pod::Coverage $min_pc required for testing POD coverage"
    if $@;

# Snake_case aliases are dynamically generated from the OpenAPI spec at load
# time by _install_snake_case_aliases; they have no POD of their own. The
# aliases are all-lowercase (some with underscores, some without) and differ
# from the camelCase/PascalCase originals. Also exclude private helpers.
#
# Load the main module first so the alias symbol table is populated, then
# query it to build an accurate exclusion regex.
BEGIN { $ENV{OPENAI_API_KEY} //= 'test-key' }
use OpenAPI::Client::OpenAI;

{
    no strict 'refs';
    my @aliases;
    for my $sym ( keys %{'OpenAPI::Client::OpenAI::'} ) {
        next unless $sym =~ /^[a-z]/;       # all installed aliases start lowercase
        next if $sym =~ /^_/;               # skip private
        push @aliases, quotemeta($sym);
    }
    my $alias_re = join '|', @aliases;
    all_pod_coverage_ok(
        {
            also_private => [
                qr/^(?:$alias_re)$/,    # dynamically installed aliases
                qr/^_/,                 # private helpers
            ],
        }
    );
}
