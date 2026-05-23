package OpenAPI::Client::OpenAI::DocGen::Markdown;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use Exporter 'import';

our @EXPORT_OK = qw(md_to_pod);

# This is a deliberately small Markdown->POD converter for the subset of
# Markdown the OpenAI spec actually uses. Known accepted limitations:
#
#   * `**foo *italic* bar**` — bold cannot span an embedded italic; the
#     non-greedy [^*]+ stops at the first asterisk. Not present in the
#     current spec.
#   * `` `code with **bold** inside` `` — backtick content is not made
#     fully literal; subsequent inline-marker passes will re-process
#     constructs inside C<...>. Not present in the current spec.
#   * `_wrap` atom regex `[BICL]<[^<>]*>` cannot handle a POD run with
#     nested angle brackets (e.g. `L<see C<foo>|url>` produced by a
#     backtick-in-link-text Markdown source). All current backtick-in-link
#     cases use the backtick as the entire link text, so the run is a
#     single \S+ atom and wraps correctly.
#
# The Phase 3.2 integration test (devel/t/docgen-integration.t) runs the
# generator against the real share/openapi.yaml and Pod::Checker catches
# any actual breakage. If a future spec update triggers one of the above,
# expand this module rather than reintroducing Markdown::Pod.

my $WRAP = 78;

sub md_to_pod ($md) {
    return '' unless defined $md && length $md;

    # Normalize CRLF.
    $md =~ s/\r\n/\n/g;

    # Split into paragraphs (blank-line separated). Process each paragraph
    # in isolation so block constructs (code fences, hrs) don't bleed.
    my @paragraphs;
    my @lines = split /\n/, $md, -1;
    my @buf;
    my $in_fence = 0;
    my $fence_buf;
    for my $line (@lines) {
        if ( $line =~ /^\s*```/ ) {
            if ($in_fence) {
                push @paragraphs, { fenced => $fence_buf };
                $in_fence  = 0;
                $fence_buf = undef;
            }
            else {
                # Flush any in-progress paragraph.
                if (@buf) {
                    push @paragraphs, { text => join( "\n", @buf ) };
                    @buf = ();
                }
                $in_fence  = 1;
                $fence_buf = '';
            }
            next;
        }
        if ($in_fence) {
            $fence_buf .= "$line\n";
            next;
        }
        if ( $line =~ /^\s*$/ ) {
            if (@buf) {
                push @paragraphs, { text => join( "\n", @buf ) };
                @buf = ();
            }
            next;
        }
        push @buf, $line;
    }
    push @paragraphs, { text => join( "\n", @buf ) } if @buf;
    push @paragraphs, { fenced => $fence_buf }       if defined $fence_buf;

    my @out;
    for my $p (@paragraphs) {
        if ( exists $p->{fenced} ) {
            my $body = $p->{fenced};
            $body =~ s/^/    /mg;    # 4-space indent = POD verbatim
            push @out, $body;
            next;
        }
        my $text = $p->{text};

        # Filter heading and hr lines individually so a body line mistakenly
        # glued to a heading without a blank separator isn't lost. Well-formed
        # input is unaffected.
        my @kept = grep {
            !/^\s*\#{1,6}\s+/                    # heading line
            && !/^\s*(?:-{3,}|\*{3,})\s*$/       # hr line
        } split /\n/, $text;

        next unless @kept;
        $text = join "\n", @kept;

        # Inline markers. Order: code first (so backticks inside emphasis
        # aren't double-processed), then bold, then italic.
        $text =~ s/`([^`]+)`/C<$1>/g;
        $text =~ s/\*\*([^*]+)\*\*/B<$1>/g;
        $text =~ s/(?<![*])\*([^*\n]+)\*(?![*])/I<$1>/g;

        # Links: rewrite /docs/ relative URLs first.
        $text =~ s{\[([^\]]+)\]\((/docs/[^)]+)\)}
                  {L<$1|https://platform.openai.com$2>}g;
        $text =~ s{\[([^\]]+)\]\(([^)]+)\)}{L<$1|$2>}g;

        # Markdown hard-breaks (two trailing spaces) -> single space.
        $text =~ s/[ ]{2,}\n/ /g;

        # Re-flow: collapse internal newlines to spaces, then wrap at 78 cols.
        $text =~ s/\n/ /g;
        $text =~ s/\s+/ /g;
        $text =~ s/^\s+|\s+$//g;

        push @out, _wrap( $text, $WRAP );
    }

    return join "\n\n", @out;
}

# Wrap on whitespace but never inside an L<...> / C<...> / B<...> / I<...>
# run. Tokenize into "POD-run" / "word" atoms (whitespace becomes inter-atom
# spacing) then greedily fill lines, allowing overflow when a single atom is
# wider than the column limit.
sub _wrap ( $text, $width ) {
    my @atoms;
    while ( length $text ) {
        if    ( $text =~ s/^\s+//          ) { next }
        elsif ( $text =~ s/^([BICL]<[^<>]*>)// ) { push @atoms, $1 }
        elsif ( $text =~ s/^(\S+)//        ) { push @atoms, $1 }
        else                                { last }
    }
    my @lines;
    my $line = '';
    for my $a (@atoms) {
        if ( !length $line ) {
            $line = $a;
        }
        elsif ( length($line) + 1 + length($a) > $width ) {
            push @lines, $line;
            $line = $a;
        }
        else {
            $line .= ' ' . $a;
        }
    }
    push @lines, $line if length $line;
    return join "\n", @lines;
}

1;
