use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use Path::Tiny;
use Pod::Checker;
use File::Find;
use OpenAPI::Client::OpenAI::DocGen;

plan skip_all => 'share/openapi.yaml not present' unless -e 'share/openapi.yaml';

my $tmp = Path::Tiny->tempdir;
OpenAPI::Client::OpenAI::DocGen->new(
    spec_file  => 'share/openapi.yaml',
    output_dir => "$tmp",
)->run;

my $baseline_file = path("$FindBin::Bin/podcheck-baseline.txt");
my $baseline = $baseline_file->exists ? 0 + $baseline_file->slurp_utf8 : 0;

my $total_errors   = 0;
my $total_warnings = 0;
my %warn_by_file;

find( sub {
    return unless /\.pod$/;
    my $file = $File::Find::name;
    my $c = Pod::Checker->new( -warnings => 1, -quiet => 1 );
    open my $sink, '>', \my $buf;
    $c->parse_from_file( $file, $sink );
    $total_errors   += $c->num_errors   // 0;
    my $w = $c->num_warnings // 0;
    $total_warnings += $w;
    $warn_by_file{$file} = $w if $w;
}, $tmp->child('lib') );

is $total_errors, 0, 'no podchecker errors across generated files';

if ( $total_warnings > $baseline ) {
    diag "Warning count $total_warnings exceeds baseline $baseline.";
    diag "Per-file warning counts:";
    for my $f ( sort { $warn_by_file{$b} <=> $warn_by_file{$a} } keys %warn_by_file ) {
        diag "  $warn_by_file{$f}\t$f";
    }
    fail "podchecker warnings regressed: $total_warnings > $baseline";
} else {
    pass "podchecker warnings within baseline ($total_warnings <= $baseline)";
}

# Guard against accidental ref stringification in rendered output (e.g.
# Default: ARRAY(0x...)). Each occurrence is both nondeterministic across
# runs and useless to readers.
my @leaks;
find( sub {
    return unless /\.pod$/;
    open my $fh, '<', $File::Find::name or return;
    local $/;
    my $body = <$fh>;
    while ( $body =~ /\b(ARRAY|HASH|CODE|GLOB|SCALAR|REF)\(0x[0-9a-f]+\)/g ) {
        push @leaks, "$File::Find::name: $1(0x...) at offset $-[0]";
    }
}, $tmp->child('lib') );

if (@leaks) {
    diag "ref-stringification leaks found:";
    diag "  $_" for @leaks;
    fail "ref-stringification leaks in generated POD";
} else {
    pass "no ref-stringification leaks in generated POD";
}

done_testing;
