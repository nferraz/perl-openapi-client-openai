use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

# Inline markers
is md_to_pod('hello **world**'), 'hello B<world>', 'bold';
is md_to_pod('say *hi*'),         'say I<hi>',      'italic';
is md_to_pod('use `foo()`'),      'use C<foo()>',   'code';

# Headings are dropped - outer POD owns hierarchy.
is md_to_pod("# H1\n\nbody"), 'body', 'h1 dropped';
is md_to_pod("## H2\n\nbody"), 'body', 'h2 dropped';

# Horizontal rule (the 80-char `=` artifact).
is md_to_pod("a\n\n---\n\nb"), "a\n\nb", 'hr dropped';
is md_to_pod("a\n\n***\n\nb"), "a\n\nb", 'hr stars dropped';

# Links - /docs/ prefix gets the platform host.
is md_to_pod('see [the docs](/docs/foo)'),
    'see L<the docs|https://platform.openai.com/docs/foo>', 'docs link';
is md_to_pod('see [GitHub](https://github.com/x)'),
    'see L<GitHub|https://github.com/x>', 'absolute link';

# Wrap at 78 columns. Build a long paragraph and verify lines.
my $long = 'word ' x 30;   # 150 chars on one logical line
my $wrapped = md_to_pod($long);
my @lines = split /\n/, $wrapped;
ok( !( grep { length($_) > 78 } @lines ),
    'every wrapped line is <=78 chars' );

# Inline runs L<...> and C<...> must not be split across lines.
my $linky = 'prefix ' . ( 'a' x 60 ) . " and `dont_split_this_code_token_xxxx` and more";
my $out = md_to_pod($linky);
unlike $out, qr/\bdont_split[^\n]*\n[^\n]*this_code/, 'C<...> stays on one line even if line overflows';

done_testing;
