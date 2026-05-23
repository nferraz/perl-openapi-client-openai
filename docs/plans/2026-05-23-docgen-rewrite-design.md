# Documentation generator rewrite — design

Date: 2026-05-23
Status: design, awaiting review
Author: brainstorming session between Ovid and Claude

## Why

`devel/build_docs.pl` is a single 415-line script that produces the per-path
POD under `lib/OpenAPI/Client/OpenAI/Path/`. Investigation of the current
output identified 10 concrete defects, the worst of which are:

- **Invalid Perl in code examples.** 110 generated examples use kebab-case
  operationIds verbatim — e.g. `$client->refer-realtime-call(...)` — which
  Perl parses as subtraction. None of these would compile.
- **`Methods.pod` is stale and orphaned.** The file claims to be generated
  but no script produces it; last modified April 2025, still references
  retired models.
- **`Markdown::Pod` emits 80-character `=` rules** in the middle of POD
  output wherever the spec uses a `---` Markdown horizontal rule.
- **JSON examples often contain nested JSON-as-strings** (41 files) or are
  effectively empty (`{"data": [null]}`, 53 files) because the example
  synthesizer doesn't handle `oneOf`/`anyOf` or already-stringified
  `x-oaiMeta.example` values.
- **105 of 174 generated files** produce `podchecker` warnings — empty
  `=over`/`=back` blocks, whitespace-only paragraphs, empty sections.
- **No tests for the generator at all**, so these defects accumulated
  silently across spec updates.

The full investigation is in conversation history; not reproduced here.

## Decisions

| Question | Decision |
|---|---|
| Ambition | Rewrite the generator |
| Doc purpose | Mirror the OpenAI spec locally — stand-alone CPAN reference |
| Schema depth | Document every property; recurse into nested objects |
| Examples | Prefer `x-oaiMeta`, fall back to schema synthesis |
| Method naming | Generalize aliasing for all operationId styles; docs use snake_case |
| Methods.pod | Auto-generate as a flat method index |
| Testing | Unit tests + end-to-end podchecker smoke test |
| Templating | Drop Template Toolkit; emit POD line-by-line in Perl |

## Architecture

Build-time tooling lives in `devel/lib/` (not installed to CPAN). Only the
shared `Naming` module ships to CPAN since the runtime needs it too.

```
devel/
  build_docs.pl                       # thin CLI: parse args, wire components, run
  lib/
    OpenAPI/Client/OpenAI/DocGen.pm   # orchestrator: takes spec, writes files
    OpenAPI/Client/OpenAI/DocGen/
      Spec.pm                         # loads YAML, indexes $refs (does not inline)
      Example.pm                      # x-oaiMeta detection + schema synthesis
      Schema.pm                       # walks request/response schemas → property records
      Markdown.pm                     # Markdown→POD with the `---`/link fixes
      Render/Path.pm                  # builds one per-path .pod
      Render/PathIndex.pm             # builds Path.pod
      Render/MethodIndex.pm           # builds Methods.pod
  t/
    docgen-naming.t
    docgen-example.t
    docgen-schema.t
    docgen-markdown.t
    docgen-render.t                   # uses tiny fixture spec
    docgen-integration.t              # full run against share/openapi.yaml + podchecker
lib/
  OpenAPI/Client/OpenAI/Naming.pm     # shipped: operationId ↔ snake_case
  OpenAPI/Client/OpenAI.pm            # uses Naming for alias generation
t/
  naming.t                            # tests for the shipped Naming module
```

No template engine. Each `Render::*` module emits POD line-by-line. The
current Template-Toolkit-in-a-heredoc is responsible for roughly half the
whitespace bugs, and POD is line-oriented anyway.

**`$ref` handling.** `Spec.pm` keeps `$ref`s unresolved — it indexes the
components and exposes the raw refs to the walkers. Both the schema walker
and the example synthesizer treat `$ref` as a discrete event: cycle
detection is by *ref target name* (a `currently-active` stack of
`#/components/schemas/Foo` entries during a single walk), not by Perl ref
address. Crossing into a named component is the marker for the depth-4
reset rule.

**`@INC` for build-time tooling.** `devel/build_docs.pl` and every
`devel/t/*.t` start with:

```perl
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
```

so they work whether invoked via `make test`, `prove`, or directly. The
shipped `Naming` module is found via `../lib` (relative to `devel/`); the
build-time `DocGen` modules via `./lib`.

## Per-path POD structure

```
=head1 NAME
=head1 DESCRIPTION                      # path-level description, if any

=head1 OPERATIONS

=head2 POST /chat/completions

=head3 createChatCompletion             # operationId verbatim (anchor target)

  $client->create_chat_completion({     # snake_case via Naming
      body => { ... },
  });

Brief summary (from spec).
Long description (markdown → POD, paragraph-wrapped to 78 cols).

=head4 Path/query parameters            # only if non-empty
  =over
    =item * C<param_name> (in path, required, string) — description
      Allowed values: foo, bar
      Default: foo
  =back

=head4 Request body                     # only if requestBody exists
Content-Type: application/json

  Properties:
  =over
    =item * C<model> (string, required) — description
      Allowed values: gpt-image-1, gpt-image-1-mini, gpt-image-1.5
      Default: gpt-image-1-mini
    =item * C<messages> (array of Message, required) — description
      See L</Message> below for item shape.
  =back

  Example:
    { "model": "gpt-image-1-mini", ... }

=head4 Responses

  B<200 — OK>
  Content-Type: application/json
  Properties: (same property-table format)
  Example: ...

=head1 SCHEMAS                          # only if request/response use named components
=head2 Message
  =over
    =item * C<role> (string, required) — ...
    =item * C<content> (string|array, required) — ...
  =back

=head1 SEE ALSO
L<OpenAPI::Client::OpenAI::Path>, L<OpenAI reference|https://...>

=head1 COPYRIGHT
```

Key differences from current output:

- No empty `=over`/`=back` blocks. A section is only emitted when it has
  content.
- Property docs precede the example. Readers grok the shape before scanning
  JSON.
- Named component schemas are documented once per `.pod` file under
  `=head1 SCHEMAS` (between OPERATIONS and SEE ALSO) and referenced via
  intra-file POD links, rather than recursing inline at every property.
  Prevents `createChatCompletion.pod` from blowing up to thousands of
  lines. A popular component like `Message` is re-emitted in every path
  file that references it; this is accepted duplication in exchange for
  self-contained per-path documentation and intra-file (not cross-file)
  links, which render reliably across POD viewers.
- For inline anonymous objects, recurse to depth 4. The depth counter
  resets to 0 each time the walker crosses a `$ref` boundary into a
  named component (so a depth-3 anonymous wrapper around a `$ref` to a
  named schema still gets the named schema fully documented under
  `=head1 SCHEMAS`). On truncation, emit a visible marker rather than
  silently dropping content:

  ```
  =item * C<image_url> (object) — nested shape omitted at depth 4;
  see the full spec at L<https://platform.openai.com/docs/api-reference>
  ```

  One stable root URL is used in every truncation marker — `x-oaiMeta.group`
  is not consulted, since not every operation has it and deep-linked URLs
  rot independently of the spec. Cycle detection: the walker maintains a
  stack of currently-active `$ref` target names; re-entering the same name
  emits the same marker rather than looping.

## Examples

`DocGen::Example` priority order:

1. `schema.x-oaiMeta.example`
2. `schema.example`
3. Method-level `x-oaiMeta.examples[0].response`
4. Synthesize from properties (only if 1–3 are missing)

The bug fix from the current generator is in `format_example`:

```perl
use JSON::PP;
my $json = JSON::PP->new->canonical->pretty;

sub format_example ($raw) {
    return undef unless defined $raw;
    if ( !ref $raw ) {
        # Already a string. Parse, then re-encode canonically.
        my $decoded = eval { $json->decode($raw) };
        return defined $decoded
            ? $json->encode($decoded)
            : undef;   # warn + omit if x-oaiMeta example isn't valid JSON
    }
    return $json->encode($raw);
}
```

The current generator wraps stringified examples in *another* JSON encode,
producing escaped-string output. This version round-trips through `decode`
to normalize.

JSON encoder choice: `JSON::PP` (core since 5.14, no XS build required,
provides both `canonical` and `pretty`). Declared as a build/dev
dependency in `Makefile.PL` (`BUILD_REQUIRES` / `TEST_REQUIRES`), not a
runtime dependency — the shipped distribution still uses `Mojo::JSON`.

Synthesis (`DocGen::Example::synthesize`):

- Walk `properties`, taking each property's `example` / `default` / first
  `enum` value, in that order.
- For arrays with `items`, recurse once and wrap in `[ ... ]`.
- For `allOf`, merge properties from every variant into one composite
  schema, then synthesize against the merged result. `allOf` semantically
  means "all variants apply," so picking one would drop the others'
  properties.
- For `oneOf` / `anyOf`, score the variants and pick the most informative
  rather than the first (which is order-dependent on YAML authoring and
  frequently the worst choice — e.g. `anyOf: [{type: string}, {enum: [...]}]`
  picks the bare string and loses the enum cue). Scoring order:

  1. A variant with its own `example` or `x-oaiMeta.example`.
  2. A variant with the most `enum`/`default` annotations.
  3. A variant with the most `properties`.
  4. The first variant (final fallback).
- For `$ref`, follow to the component. The depth counter resets to 0
  on crossing into a named component, matching the schema walker's rule.
- Track currently-active `$ref` target names on a stack; re-entering the
  same name emits a visible truncation marker (a JSON-valid sentinel like
  `"...": "..."`) rather than looping.
- Stop at recursion depth 4. On truncation, emit the same JSON-valid
  sentinel marker so the truncation is visible in the rendered example
  rather than silently dropped.

All output uses canonical key ordering for reproducible diffs across spec
updates.

## Markdown→POD

A small replacement for `Markdown::Pod` in `DocGen::Markdown`:

| Markdown | POD |
|---|---|
| `# H1`, `## H2` | drop the heading line entirely (the outer POD owns hierarchy) |
| `**X**` | `B<X>` |
| `*X*` | `I<X>` |
| `` `X` `` | `C<X>` |
| `[t](u)` | `L<t\|u>`; if `u` starts with `/docs/`, prepend `https://platform.openai.com` |
| `---`, `***` | drop entirely (this is the source of the 80-char `=` artifact) |
| Paragraph | preserve blank-line separation; wrap to 78 cols (see below) |
| ```` ```lang … ``` ```` | POD indent block (4 spaces) |

Approximately 80 lines of regex + line walker. Fully unit-testable. Removes
the `Markdown::Pod` dependency.

**Wrap rules.** Plain paragraphs wrap at 78 columns (conventional CPAN
width; diff churn on spec updates is the accepted cost). `=item`
continuation lines are *not* re-wrapped — the renderer handles them, and
wrapping at a fixed column inside variable indentation produces ragged
output. `L<...>` and `C<...>` runs are never broken across lines; if a
single token would push the line past 78, the line overflows rather than
splitting the inline. Markdown hard-breaks (two trailing spaces) collapse
to a single space, since POD doesn't have a clean equivalent.

## Naming

`OpenAPI::Client::OpenAI::Naming::to_snake_case($operationId)` — pure
function, shipped with the distribution (the runtime needs it for alias
generation).

| Input style | Example | Output |
|---|---|---|
| camelCase | `createChatCompletion` | `create_chat_completion` |
| PascalCase | `ListSkills` | `list_skills` |
| kebab-case | `refer-realtime-call` | `refer_realtime_call` |
| snake_case | `usage_audio_speeches` | unchanged |
| Mixed | `admin-api-keys-list` | `admin_api_keys_list` |
| Consecutive caps | `APIKey` | `api_key` |

`lib/OpenAPI/Client/OpenAI.pm`: extend the existing camelCase alias loop to
call `to_snake_case` on every operationId, so every operation has a
snake_case callable form. The original operationId (whatever its style)
also continues to work, since `OpenAPI::Client` generates that method
directly.

**Both forms are first-class.** The existing six snake_case aliases
(`create_chat_completion`, `create_completion`, `create_embedding`,
`create_image`, `create_moderation`, `list_models`) currently emit a
deprecation warning and the shipped POD has a `=head1 DEPRECATED METHODS`
section. This rewrite reverses that: drop the warning, remove the
DEPRECATED METHODS section, and document snake_case as the recommended
Perl-idiomatic form with camelCase as a still-supported alias. Add a
Changes entry noting the policy reversal.

**Collision guard.** Two distinct operationIds could map to the same
snake_case form (e.g. an already-snake_case `usage_audio_speeches` and a
hypothetical camelCase `usageAudioSpeeches`, or `APIKey` and `apiKey` both
→ `api_key`). The alias loop must detect this at install time and
`croak` with both operationIds named, rather than silently letting one
clobber the other. Tested in `t/naming.t` with a fixture spec that
intentionally collides.

## Indexes

**`Path.pod` (by URL)** — keep its current role; tweak content:

```
=head2 /chat/completions
  =over
    =item * C<GET>  list_chat_completions — List stored Chat Completions
    =item * C<POST> create_chat_completion — Creates a model response …
  =back
  See L<OpenAPI::Client::OpenAI::Path::chat-completions>.
```

Each method line now shows the snake_case Perl method alongside the verb —
the bridge between "I want to list chat completions" and "what do I call?".

**`Methods.pod` (by method name)** — newly auto-generated, alphabetical:

```
=head2 create_chat_completion
  POST /chat/completions
  operationId: createChatCompletion
  Creates a model response …
  See L<OpenAPI::Client::OpenAI::Path::chat-completions>.
```

~5 lines per method. At ~250 methods, this is ~1500 lines: readable,
greppable, and diffs cleanly across spec updates.

## Testing

Unit tests for the small pure modules (`Naming`, `Example`, `Markdown`,
`Schema`). Each module has its own `.t` file with focused cases.

One integration test (`devel/t/docgen-integration.t`) runs the full
generator against the real `share/openapi.yaml`, then iterates every
generated POD file and runs `Pod::Checker` on it. The pass criteria:

- **Errors:** any error fails the test, unconditionally.
- **Warnings:** failure only when the total warning count exceeds a
  baseline committed at `devel/t/podcheck-baseline.txt` (one integer:
  the accepted ceiling). The rewrite's goal is to drive this to zero;
  the baseline records the current ceiling so regressions surface
  without chasing every cosmetic Pod::Checker opinion across
  Pod::Checker version bumps.

When intentional improvements lower the count, re-bless the baseline in
the same commit. The test prints a diff (per-file warning counts) on
failure so the cause is obvious.

This catches whole-program regressions without committing snapshot files
(which would churn on every spec update) and without making the suite
hostage to upstream Pod::Checker changes.

Tests for the runtime alias change (including the collision guard) live
in `t/naming.t` and a small addition to whatever currently exercises
`lib/OpenAPI/Client/OpenAI.pm`.

### Wiring DocGen tests into `make test`

Pass a `test` key to `WriteMakefile` so EU::MM discovers both directories:

```perl
WriteMakefile(
    ...
    test => { TESTS => 't/*.t devel/t/*.t' },
);
```

This is the documented `ExtUtils::MakeMaker` hook for extending the test
file set — no `MY::test` override, no regex surgery on generated Makefile
fragments. The migration claim ("`RELEASE_TESTING=1 make test` passes
after every step") becomes true cleanly: the DocGen unit tests run for the
scaffolding commit, and the integration test gates the wire-up commit.

### Keeping DocGen out of the CPAN tarball

`devel/lib/` and `devel/t/` are build-time tooling. They should be present
in the git repo but excluded from `make dist`. Add to `MANIFEST.SKIP`:

```
^devel/lib/
^devel/t/
```

`devel/build_docs.pl`, `devel/rebuild`, and `devel/tag-release` continue
to ship as today.

## Migration

Four commits, each independently verifiable (`RELEASE_TESTING=1 make test`
passes after every step):

1. **Runtime alias generalization.** Add `OpenAPI::Client::OpenAI::Naming`.
   Extend alias loop in `OpenAPI::Client::OpenAI` to cover all operationId
   styles with a collision guard. Remove the deprecation warning from the
   existing six snake_case aliases and the `=head1 DEPRECATED METHODS`
   section from the module POD. Unit tests for `Naming` (including a
   collision-detection test). Generated docs unchanged.
2. **Generator scaffolding.** Add `devel/lib/OpenAPI/Client/OpenAI/DocGen*`
   modules with full implementations and unit tests. `devel/build_docs.pl`
   still uses the *old* logic. Generated docs unchanged.
3. **Wire DocGen in, regenerate.** Switch `build_docs.pl` to use DocGen.
   Regenerate all POD files, regenerate MANIFEST. Large diff (~180 files)
   but one logical change: "the generator is different; here's its
   output."
4. **Delete old code.** Remove dead helpers from the old script. Keeps
   step 3 reviewable by isolating *new* code from *removed* code.

No CPAN release until all four land. Then bump to 0.27 with one Changes
entry summarizing the documentation overhaul.

## Out of scope

The following came up during investigation but are deliberately left for
later:

- Renaming `Path.pod` / `Path/*.pod` to something more idiomatic. The path
  layout works; changing it would break inbound links.
- Markdown output alongside POD. CPAN consumers expect POD; if Markdown is
  wanted, it can be regenerated from POD via `pod2markdown`.
- A standalone CLI for "generate docs for one path." Useful for iteration
  but not load-bearing for the rewrite.
