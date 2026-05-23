use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use Path::Tiny;
use OpenAPI::Client::OpenAI::DocGen;

my $out = Path::Tiny->tempdir;
my $gen = OpenAPI::Client::OpenAI::DocGen->new(
    spec_file  => "$FindBin::Bin/fixtures/tiny-spec.yaml",
    output_dir => "$out",
);
$gen->run;

ok -e "$out/lib/OpenAPI/Client/OpenAI/Path.pod",         'Path.pod written';
ok -e "$out/lib/OpenAPI/Client/OpenAI/Methods.pod",      'Methods.pod written';
ok -e "$out/lib/OpenAPI/Client/OpenAI/Path/things.pod",  'per-path POD written';

done_testing;
