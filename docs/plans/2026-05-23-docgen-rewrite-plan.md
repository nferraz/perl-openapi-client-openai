# Documentation Generator Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single 415-line `devel/build_docs.pl` with a modular, tested generator that produces clean POD for every OpenAI API path, an auto-generated method index, and ships a `Naming` module so the runtime offers both `createChatCompletion` and `create_chat_completion` as first-class call forms.

**Architecture:** Build-time tooling moves to `devel/lib/OpenAPI/Client/OpenAI/DocGen*` (not installed to CPAN). The only new shipped module is `OpenAPI::Client::OpenAI::Naming` (pure function, used by the runtime alias loop). Each `DocGen::*` module has one responsibility; `Render::*` modules emit POD line-by-line (no template engine). All `$ref`s stay unresolved — walkers treat them as discrete events with cycle detection by target name.

**Tech Stack:** Perl 5.26+ (signatures, indented heredocs), `YAML::XS`, `JSON::PP` (core), `Pod::Checker` (core), `Path::Tiny`. Drops `Markdown::Pod` and `Template` from build deps.

**Source design:** `docs/plans/2026-05-23-docgen-rewrite-design.md` — this plan operationalizes that design as bite-sized TDD steps. When a step says "implement per design §X", that section has the full algorithm.

**Verification gate after every commit:** `RELEASE_TESTING=1 make test` must pass. State this gate explicitly at the end of each phase.

---

## Phase 1 — Runtime alias generalization (Commit 1)

**Why first:** Independent of the generator rewrite. Ships immediately useful behavior (snake_case as first-class) and the shared `Naming` module that later phases consume.

### Task 1.1: Create `Naming::to_snake_case`

**Files:**
- Create: `lib/OpenAPI/Client/OpenAI/Naming.pm`
- Create: `t/naming.t`

- [ ] **Step 1: Write the failing test**

Create `t/naming.t`:

```perl
use strict;
use warnings;
use Test::Most;
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);

my @cases = (
    [ 'createChatCompletion'  => 'create_chat_completion' ],
    [ 'ListSkills'            => 'list_skills' ],
    [ 'refer-realtime-call'   => 'refer_realtime_call' ],
    [ 'usage_audio_speeches'  => 'usage_audio_speeches' ],
    [ 'admin-api-keys-list'   => 'admin_api_keys_list' ],
    [ 'APIKey'                => 'api_key' ],
    [ 'OAuth2Token'           => 'o_auth2_token' ],   # documents the chosen behavior for digit boundaries
    [ 'listModels'            => 'list_models' ],
);

for my $case (@cases) {
    my ( $in, $want ) = @$case;
    is to_snake_case($in), $want, "to_snake_case('$in')";
}

done_testing;
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `prove -lv t/naming.t`
Expected: FAIL with `Can't locate OpenAPI/Client/OpenAI/Naming.pm`.

- [ ] **Step 3: Implement `Naming.pm`**

```perl
package OpenAPI::Client::OpenAI::Naming;

use 5.014;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(to_snake_case);

# Convert any of camelCase, PascalCase, kebab-case, snake_case, or mixed
# to snake_case. Pure function; the runtime alias loop and the docgen
# both depend on this producing stable, collision-detectable output.
sub to_snake_case {
    my ($name) = @_;
    return $name unless defined $name && length $name;

    # kebab → snake first so we can treat the rest as a single identifier.
    $name =~ s/-/_/g;

    # Insert underscore between a run of capitals and a following Capital+lowercase
    # (handles "APIKey" → "API_Key", "HTTPServer" → "HTTP_Server").
    $name =~ s/([A-Z]+)([A-Z][a-z])/${1}_${2}/g;

    # Insert underscore between lowercase/digit and an uppercase letter
    # (handles "createChat" → "create_Chat").
    $name =~ s/([a-z\d])([A-Z])/${1}_${2}/g;

    # Collapse any doubled underscores from already-snake input mixed with the above.
    $name =~ s/_+/_/g;

    return lc $name;
}

1;
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `prove -lv t/naming.t`
Expected: PASS, 8 ok.

If `OAuth2Token` produces something other than `o_auth2_token`, update the test to match the actual behavior — the goal is documented determinism, not a specific stylistic choice. Then move on.

- [ ] **Step 5: Add collision-detection helper test**

Append to `t/naming.t` before `done_testing`:

```perl
# Collision detection is the alias loop's job, but Naming exposes a helper
# so the loop and tests share one implementation.
use OpenAPI::Client::OpenAI::Naming qw(detect_collisions);

is_deeply
    detect_collisions( [qw(createChatCompletion create_chat_completion)] ),
    { create_chat_completion => [qw(createChatCompletion create_chat_completion)] },
    'detects camel/snake colliding to same snake form';

is_deeply
    detect_collisions( [qw(listModels listSkills)] ),
    {},
    'no collision when snake forms differ';
```

- [ ] **Step 6: Implement `detect_collisions`**

Append to `Naming.pm` before the `1;`:

```perl
push @EXPORT_OK, 'detect_collisions';

sub detect_collisions {
    my ($operation_ids) = @_;
    my %by_snake;
    for my $op (@$operation_ids) {
        push @{ $by_snake{ to_snake_case($op) } }, $op;
    }
    # Only return entries with more than one source operationId.
    return {
        map  { $_ => [ sort @{ $by_snake{$_} } ] }
        grep { @{ $by_snake{$_} } > 1 } keys %by_snake
    };
}
```

(Move the `push @EXPORT_OK, 'detect_collisions'` next to the existing `our @EXPORT_OK = (...)` if you prefer one declaration.)

- [ ] **Step 7: Run the test, verify it passes**

Run: `prove -lv t/naming.t`
Expected: PASS, 10 ok.

- [ ] **Step 8: Commit**

```bash
git add lib/OpenAPI/Client/OpenAI/Naming.pm t/naming.t
git commit -m "Add OpenAPI::Client::OpenAI::Naming for shared snake_case conversion"
```

### Task 1.1b: Collision fixture spec + integration test

**Files:**
- Create: `t/fixtures/colliding-spec.yaml`
- Create: `t/alias_collision.t`

The unit test in Task 1.1 covers `detect_collisions` as a pure function. The design (lines 320-324) also asks for a fixture-spec test exercising the croak path through `OpenAPI::Client::OpenAI->new`. This task lands the fixture and test now so the croak is wired-test-covered when Task 1.2 lands the alias loop.

- [ ] **Step 1: Create the fixture spec**

`t/fixtures/colliding-spec.yaml`:

```yaml
openapi: 3.0.0
info:
  title: Collision Fixture
  version: '1.0'
paths:
  /thing-a:
    post:
      operationId: createThing
      responses: { '200': { description: ok } }
  /thing-b:
    post:
      operationId: create_thing
      responses: { '200': { description: ok } }
```

`createThing` → `create_thing`; the already-snake `create_thing` is unchanged. Both map to the same snake form — collision.

- [ ] **Step 2: Write the failing test**

`t/alias_collision.t`:

```perl
use strict;
use warnings;
use Test::Most;

BEGIN { $ENV{OPENAI_API_KEY} //= 'test-key' }

# The collision guard fires at module load if the loaded spec collides. We
# bypass that by stubbing the spec path to our fixture before the alias loop
# runs. Since require time and runtime are the same here, we test the
# collision-detection helper directly against the fixture and assert the
# message format the alias loop will use.
use OpenAPI::Client::OpenAI::Naming qw(detect_collisions);
use YAML::XS qw(LoadFile);

my $spec = LoadFile('t/fixtures/colliding-spec.yaml');
my @op_ids;
for my $path ( values %{ $spec->{paths} } ) {
    for my $method ( values %$path ) {
        next unless ref $method eq 'HASH' && $method->{operationId};
        push @op_ids, $method->{operationId};
    }
}

my $collisions = detect_collisions( \@op_ids );
ok exists $collisions->{create_thing}, 'create_thing collision detected';
is_deeply $collisions->{create_thing},
    [ sort qw(createThing create_thing) ],
    'both operationIds named in the collision entry';

done_testing;
```

(Task 1.2 will reuse this fixture in a second test that loads it through `OpenAPI::Client::OpenAI->new(spec_file => ...)` and asserts the actual croak — added as Step 1b in Task 1.2 below.)

- [ ] **Step 3: Run, verify pass**

Run: `prove -lv t/alias_collision.t`
Expected: PASS, 2 ok. (The Naming module already exists from Task 1.1.)

- [ ] **Step 4: Commit**

```bash
git add t/fixtures/colliding-spec.yaml t/alias_collision.t
git commit -m "Add colliding-spec fixture; test detect_collisions identifies both ops"
```

### Task 1.2: Generalize the alias loop in `OpenAPI::Client::OpenAI`

**Files:**
- Modify: `lib/OpenAPI/Client/OpenAI.pm` (lines 61-82 — the existing alias block)
- Create: `t/alias_generalization.t`

- [ ] **Step 1: Write the failing test**

Create `t/alias_generalization.t`:

```perl
use strict;
use warnings;
use Test::Most;

BEGIN { $ENV{OPENAI_API_KEY} //= 'test-key' }
use OpenAPI::Client::OpenAI;

my $client = OpenAPI::Client::OpenAI->new;

# Sampling: a camelCase op, a kebab-case op (if the spec has any), and the
# legacy six. Each should be callable in both original and snake_case form.
ok $client->can('createChatCompletion'),  'camelCase original is callable';
ok $client->can('create_chat_completion'), 'snake_case alias is callable';

ok $client->can('listModels'),  'listModels original';
ok $client->can('list_models'), 'list_models alias';

# The deprecation warning is gone after this commit.
my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };
# We don't actually send the request; just make the method exist and not warn
# at resolution time. Calling it would hit the network.
ok defined &OpenAPI::Client::OpenAI::create_chat_completion,
    'snake_case alias defined';
is scalar(@warnings), 0, 'no deprecation warning emitted at load time';

done_testing;
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `prove -lv t/alias_generalization.t`

Expected: FAIL — the existing alias loop only covers six methods, so most snake_case forms aren't defined yet, AND loading the module emits deprecation warnings as soon as any deprecated alias is invoked (the warnings live in the alias sub, so the load-time check may already pass; the failure should be on missing aliases for camelCase ops outside the legacy six).

- [ ] **Step 3: Rewrite the alias block in `OpenAPI/Client/OpenAI.pm`**

Replace lines 61-82 (the existing `install snake case aliases` block) with:

```perl
# Install snake_case aliases for every operationId in the spec.
# Both forms are first-class; the original (whatever its style) is generated
# by OpenAPI::Client and the snake_case version is generated here.
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case detect_collisions);

sub _install_snake_case_aliases {
    my ($operation_ids) = @_;

    my $collisions = detect_collisions($operation_ids);
    if ( %$collisions ) {
        my @msgs;
        for my $snake ( sort keys %$collisions ) {
            push @msgs, "  $snake <- " . join( ', ', @{ $collisions->{$snake} } );
        }
        Carp::croak(
            "operationId collision in OpenAPI spec: multiple operations map "
            . "to the same snake_case alias:\n" . join("\n", @msgs)
        );
    }

    for my $op (@$operation_ids) {
        my $snake = to_snake_case($op);
        next if $snake eq $op;   # already snake_case, nothing to install
        no strict 'refs';
        next if defined &{$snake};  # safety: don't clobber an existing method
        *$snake = sub {
            my $self = shift;
            $self->$op(@_);
        };
    }
}

sub _operation_ids_from_spec_file {
    my ($spec_path) = @_;
    require YAML::XS;
    my $spec = YAML::XS::LoadFile($spec_path);
    my @ids;
    for my $path ( values %{ $spec->{paths} || {} } ) {
        for my $method ( values %$path ) {
            next unless ref $method eq 'HASH' && $method->{operationId};
            push @ids, $method->{operationId};
        }
    }
    return \@ids;
}

# Module-load: install aliases for the shipped spec.
{
    my $spec_path = eval {
        File::ShareDir::dist_file( 'OpenAPI-Client-OpenAI', 'openapi.yaml' );
    } || catfile( 'share', 'openapi.yaml' );

    _install_snake_case_aliases( _operation_ids_from_spec_file($spec_path) );
}
```

This block runs once at module load time, scanning the spec file directly. No deprecation warning. The two private subs (`_install_snake_case_aliases`, `_operation_ids_from_spec_file`) are extracted so tests can drive the install logic against fixture specs without re-loading the module. Note that `YAML::XS` is already in `BUILD_REQUIRES`; promote it to `PREREQ_PM` (see Step 4).

- [ ] **Step 4: Promote `YAML::XS` to runtime prereq**

In `Makefile.PL`, move `'YAML::XS' => '0'` from `BUILD_REQUIRES` to `PREREQ_PM`. The runtime now needs it for the alias loop. Keep it listed in `BUILD_REQUIRES` too if EU::MM doesn't dedupe — duplicates are harmless.

- [ ] **Step 4b: Extend `t/alias_collision.t` with the croak path**

Append to `t/alias_collision.t` (the test file created in Task 1.1b) before `done_testing`:

```perl
# End-to-end: feed the fixture's operationIds through the extracted alias
# installer and assert it croaks with both source operationIds in the message.
use OpenAPI::Client::OpenAI;

throws_ok {
    OpenAPI::Client::OpenAI::_install_snake_case_aliases( \@op_ids );
} qr/createThing/, 'croak names createThing';
throws_ok {
    OpenAPI::Client::OpenAI::_install_snake_case_aliases( \@op_ids );
} qr/create_thing/, 'croak names create_thing';
throws_ok {
    OpenAPI::Client::OpenAI::_install_snake_case_aliases( \@op_ids );
} qr/collision/i, 'croak message mentions "collision"';
```

Run: `prove -lv t/alias_collision.t`
Expected: PASS, 5 ok total (the 2 from Task 1.1b plus 3 new).

- [ ] **Step 5: Run the alias test, verify it passes**

Run: `prove -lv t/alias_generalization.t`
Expected: PASS, 5 ok.

- [ ] **Step 6: Run the full test suite**

Run: `perl Makefile.PL && make && RELEASE_TESTING=1 make test`
Expected: PASS. (Network tests skip without `OPENAI_API_KEY` and live access; that's fine.)

- [ ] **Step 7: Commit**

```bash
git add lib/OpenAPI/Client/OpenAI.pm Makefile.PL t/alias_generalization.t t/alias_collision.t
git commit -m "Generate snake_case aliases for every operationId; drop deprecation"
```

### Task 1.3: Remove `=head1 DEPRECATED METHODS` from main module POD

**Files:**
- Modify: `lib/OpenAPI/Client/OpenAI.pm` (lines 173-207 — the DEPRECATED METHODS section)

- [ ] **Step 1: Remove the section**

Delete lines starting at `=head1 DEPRECATED METHODS` through (but not including) `=head1 ENVIRONMENT VARIABLES`. Also update the surrounding text:

- Line 167-168 currently reads:
  > Other methods are documented in L<OpenAPI::Client::OpenAI::Methods>. These
  > method are deprecated and will be removed in a future version.

  Change to:
  > Other methods are documented in L<OpenAPI::Client::OpenAI::Methods>. Every
  > API operation is callable in both its original (e.g. C<createChatCompletion>)
  > and snake_case (e.g. C<create_chat_completion>) form.

- [ ] **Step 2: Run pod tests**

Run: `prove -lv t/pod.t t/pod-coverage.t`
Expected: PASS.

- [ ] **Step 3: Add a Changes entry**

Prepend to `Changes` under the existing `0.26` block — or add a new `0.27 (dev)` block if 0.26 is already released. Inspect `Changes` to choose. Use this entry:

```
0.27    (dev)

        - Snake_case aliases for every operation: every operationId is
          callable in both its original style (e.g. createChatCompletion)
          and snake_case (e.g. create_chat_completion). Both forms are
          first-class; the deprecation warning on the legacy six aliases
          is removed.
```

- [ ] **Step 4: Run the full suite again**

Run: `RELEASE_TESTING=1 make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/OpenAPI/Client/OpenAI.pm Changes
git commit -m "Document snake_case aliases as first-class; remove deprecation POD"
```

**Phase 1 gate:** `RELEASE_TESTING=1 make test` passes. Generated POD files under `lib/OpenAPI/Client/OpenAI/Path*` are byte-identical to before this phase — confirm with `git diff lib/OpenAPI/Client/OpenAI/Path*` showing no output.

---

## Phase 2 — Generator scaffolding (Commit 2)

**Why next:** Build the new generator in `devel/lib/` alongside the old one. Old `build_docs.pl` still produces output; new modules are exercised only by unit tests. No POD churn yet.

### Task 2.1: `devel/lib/` skeleton + Makefile wiring

**Files:**
- Modify: `Makefile.PL` (add `test` key, add `JSON::PP` to TEST_REQUIRES)
- Modify: `MANIFEST.skip` (exclude `devel/lib/` and `devel/t/`)
- Create: `devel/lib/.gitkeep`, `devel/t/.gitkeep` (empty placeholder)

- [ ] **Step 1: Extend `WriteMakefile` args**

In `Makefile.PL`, inside the `%WriteMakefileArgs` hash, add:

```perl
    test => { TESTS => 't/*.t devel/t/*.t' },
```

This is `ExtUtils::MakeMaker`'s documented hook for extending the test set.

Add to `TEST_REQUIRES` (existing hash):

```perl
        'JSON::PP'    => '0',
        'Pod::Checker' => '0',
```

Both are core in 5.14+, so declaring them is paperwork — but it's what CPANTS will check.

- [ ] **Step 2: Update `MANIFEST.skip`**

Append:

```
^devel/lib/
^devel/t/
```

(After confirming the file uses Perl regex format — current contents are `.git`, `.DS_Store`, etc., one per line as anchored patterns. Match the existing style. If `^devel/build_docs.pl` is *not* present, the script will still ship because no rule excludes it.)

- [ ] **Step 3: Verify the test target picks up `devel/t/`**

```bash
mkdir -p devel/t devel/lib
echo 'use Test::More; ok 1; done_testing;' > devel/t/sanity.t
perl Makefile.PL
make test
```

Expected: the new `devel/t/sanity.t` runs and passes alongside the existing tests.

- [ ] **Step 4: Verify the dist tarball excludes `devel/lib` and `devel/t`**

```bash
make manifest    # regenerates MANIFEST
make distdir     # creates a staging dir
ls OpenAPI-Client-OpenAI-*/devel/   # should show build_docs.pl, rebuild, etc. — NOT lib/ or t/
rm -rf OpenAPI-Client-OpenAI-*
```

Expected: `devel/lib/` and `devel/t/` absent from staging.

- [ ] **Step 5: Remove the sanity test, leave `.gitkeep`**

```bash
rm devel/t/sanity.t
touch devel/t/.gitkeep devel/lib/.gitkeep
```

- [ ] **Step 6: Commit**

```bash
git add Makefile.PL MANIFEST.skip devel/t/.gitkeep devel/lib/.gitkeep
git commit -m "Wire devel/t/ into make test; exclude devel/lib and devel/t from dist"
```

### Task 2.2: `DocGen::Spec` — YAML loader with ref index

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Spec.pm`
- Create: `devel/t/docgen-spec.t`
- Create: `devel/t/fixtures/tiny-spec.yaml`

- [ ] **Step 1: Create a tiny fixture spec**

`devel/t/fixtures/tiny-spec.yaml`:

```yaml
openapi: 3.0.0
info:
  title: Tiny
  version: '1.0'
paths:
  /things:
    post:
      operationId: createThing
      summary: Make a thing
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Thing'
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Thing'
components:
  schemas:
    Thing:
      type: object
      properties:
        name: { type: string }
        size: { type: integer, default: 10 }
```

- [ ] **Step 2: Write the failing test**

`devel/t/docgen-spec.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);

ok $spec, 'loaded';
is_deeply [ sort keys %{ $spec->paths } ], ['/things'], 'paths indexed';

my $thing = $spec->resolve_ref('#/components/schemas/Thing');
is $thing->{type}, 'object', 'ref resolution works';

is $spec->ref_name('#/components/schemas/Thing'), 'Thing', 'ref_name strips prefix';

# Refs in the loaded tree are NOT inlined.
my $body_schema =
    $spec->paths->{'/things'}{post}{requestBody}{content}{'application/json'}{schema};
is_deeply $body_schema, { '$ref' => '#/components/schemas/Thing' },
    'refs in path tree remain unresolved';

done_testing;
```

- [ ] **Step 3: Run, verify fail**

Run: `prove -l devel/t/docgen-spec.t`
Expected: FAIL — `Can't locate OpenAPI/Client/OpenAI/DocGen/Spec.pm`.

- [ ] **Step 4: Implement `DocGen::Spec`**

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Spec.pm`:

```perl
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

sub paths ($self) { $self->{raw}{paths} }
sub components ($self) { $self->{raw}{components} || {} }
sub raw ($self) { $self->{raw} }

# '#/components/schemas/Thing' -> 'Thing'
sub ref_name ( $self, $ref ) {
    my @parts = split '/', $ref;
    return $parts[-1];
}

# Resolve a JSON pointer like '#/components/schemas/Thing' against the spec.
# Does NOT inline anywhere — callers consume the result directly, they don't
# splice it back into the tree.
sub resolve_ref ( $self, $ref ) {
    croak "expected ref starting with '#/', got '$ref'" unless $ref =~ m{^#/};
    my @parts = split '/', substr( $ref, 2 );
    my $node = $self->{raw};
    for my $part (@parts) {
        $part =~ s{~1}{/}g;
        $part =~ s{~0}{~}g;
        $node = $node->{$part} // croak "cannot resolve $ref (no '$part')";
    }
    return $node;
}

1;
```

- [ ] **Step 5: Run, verify pass**

Run: `prove -l devel/t/docgen-spec.t`
Expected: PASS, 5 ok.

- [ ] **Step 6: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Spec.pm devel/t/docgen-spec.t devel/t/fixtures/tiny-spec.yaml
git commit -m "Add DocGen::Spec: YAML loader with non-inlining $ref resolution"
```

### Task 2.3: `DocGen::Markdown` — Markdown → POD converter

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Markdown.pm`
- Create: `devel/t/docgen-markdown.t`

- [ ] **Step 1: Write the failing test**

`devel/t/docgen-markdown.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

# Inline markers
is md_to_pod('hello **world**'), 'hello B<world>', 'bold';
is md_to_pod('say *hi*'),         'say I<hi>',      'italic';
is md_to_pod('use `foo()`'),      'use C<foo()>',   'code';

# Headings are dropped — outer POD owns hierarchy.
is md_to_pod("# H1\n\nbody"), 'body', 'h1 dropped';
is md_to_pod("## H2\n\nbody"), 'body', 'h2 dropped';

# Horizontal rule (the 80-char `=` artifact).
is md_to_pod("a\n\n---\n\nb"), "a\n\nb", 'hr dropped';
is md_to_pod("a\n\n***\n\nb"), "a\n\nb", 'hr stars dropped';

# Links — /docs/ prefix gets the platform host.
is md_to_pod('see [the docs](/docs/foo)'),
    'see L<the docs|https://platform.openai.com/docs/foo>', 'docs link';
is md_to_pod('see [GitHub](https://github.com/x)'),
    'see L<GitHub|https://github.com/x>', 'absolute link';

# Wrap at 78 columns. Build a long paragraph and verify lines.
my $long = 'word ' x 30;   # 150 chars on one logical line
chomp(my $wrapped = md_to_pod($long));
ok( ( length($_) <= 78 ) for split /\n/, $wrapped ),
    'every wrapped line is <=78 chars';

# Inline runs L<...> and C<...> must not be split across lines.
my $linky = 'prefix ' . ( 'a' x 60 ) . " and `dont_split_this_code_token_xxxx` and more";
my $out = md_to_pod($linky);
unlike $out, qr/\n[^\n]*dont_split/m, 'C<...> stays on one line even if line overflows';

done_testing;
```

- [ ] **Step 2: Run, verify fail**

Run: `prove -l devel/t/docgen-markdown.t`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `DocGen::Markdown`**

Per design §"Markdown→POD" (lines 262-286). The skeleton:

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Markdown.pm`:

```perl
package OpenAPI::Client::OpenAI::DocGen::Markdown;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use Exporter 'import';

our @EXPORT_OK = qw(md_to_pod);

my $WRAP = 78;

sub md_to_pod ($md) {
    return '' unless defined $md && length $md;

    # Normalize CRLF, strip leading/trailing whitespace blocks.
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
                $in_fence = 0;
                $fence_buf = undef;
            } else {
                # Flush any in-progress paragraph.
                if (@buf) { push @paragraphs, { text => join("\n", @buf) }; @buf = (); }
                $in_fence = 1;
                $fence_buf = '';
            }
            next;
        }
        if ($in_fence) {
            $fence_buf .= "$line\n";
            next;
        }
        if ( $line =~ /^\s*$/ ) {
            if (@buf) { push @paragraphs, { text => join("\n", @buf) }; @buf = (); }
            next;
        }
        push @buf, $line;
    }
    push @paragraphs, { text => join("\n", @buf) } if @buf;
    push @paragraphs, { fenced => $fence_buf }     if defined $fence_buf;

    my @out;
    for my $p (@paragraphs) {
        if ( exists $p->{fenced} ) {
            my $body = $p->{fenced};
            $body =~ s/^/    /mg;   # 4-space indent = POD verbatim
            push @out, $body;
            next;
        }
        my $text = $p->{text};

        # Drop heading lines and HR lines entirely.
        next if $text =~ /^\s*\#{1,6}\s+/;
        next if $text =~ /^\s*(?:-{3,}|\*{3,})\s*$/;

        # Inline markers (order matters: code before bold/italic so backticks
        # inside emphasis aren't double-processed).
        $text =~ s/`([^`]+)`/C<$1>/g;
        $text =~ s/\*\*([^*]+)\*\*/B<$1>/g;
        $text =~ s/(?<![*])\*([^*\n]+)\*(?![*])/I<$1>/g;

        # Links — rewrite /docs/ relative URLs first.
        $text =~ s{\[([^\]]+)\]\((/docs/[^)]+)\)}
                  {L<$1|https://platform.openai.com$2>}g;
        $text =~ s{\[([^\]]+)\]\(([^)]+)\)}{L<$1|$2>}g;

        # Markdown hard-breaks (two trailing spaces) → single space.
        $text =~ s/[ ]{2,}\n/ /g;

        # Re-flow: collapse internal newlines to spaces, then wrap at 78
        # columns honoring atomic L<...> / C<...> runs.
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
        if    ( $text =~ s/^\s+// )                  { next }
        elsif ( $text =~ s/^([BICL]<[^<>]*>)// )     { push @atoms, $1 }
        elsif ( $text =~ s/^(\S+)// )                { push @atoms, $1 }
        else                                         { last }
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
```

- [ ] **Step 4: Run, verify pass**

Run: `prove -l devel/t/docgen-markdown.t`
Expected: PASS. If specific test cases fail, fix the regexes — the wrapping or escaping is the most likely culprit.

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Markdown.pm devel/t/docgen-markdown.t
git commit -m "Add DocGen::Markdown: md->POD with hr drop, /docs/ link rewrite, 78-col wrap"
```

### Task 2.4: `DocGen::Example` — example resolution + JSON synthesis

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Example.pm`
- Create: `devel/t/docgen-example.t`

- [ ] **Step 1: Write the failing test**

`devel/t/docgen-example.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Most;
use JSON::PP qw(decode_json);
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $ex = OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec );

# format_example: round-trips stringified JSON, encodes refs.
is $ex->format_example(undef), undef, 'undef in -> undef out';
is $ex->format_example('{"a":1}'),
    qq({\n   "a" : 1\n}), 'string JSON re-encoded canonically';
is $ex->format_example('not-json-at-all'), undef, 'invalid JSON -> undef (warned)';
like $ex->format_example({ b => 2, a => 1 }),
    qr/"a"\s*:\s*1.*"b"\s*:\s*2/s, 'hash ref encoded canonically';

# Synthesis: walks properties of a schema (no example present), drilling into
# refs, with depth cap at 4 and visible truncation marker.
my $synth = $ex->synthesize_for( $spec->resolve_ref('#/components/schemas/Thing') );
is_deeply $synth, { name => 'string', size => 10 }, 'enum/default/scalar fallback';

# oneOf scoring: prefer the variant with its own example or with the most
# enum/default annotations.
my $oneof = {
    oneOf => [
        { type => 'string' },
        { type => 'string', enum => [ 'a', 'b' ] },
    ],
};
is $ex->synthesize_for($oneof), 'a', 'oneOf picks enum-bearing variant';

# resolve_example: priority chain per design §Examples.
# 1. schema.x-oaiMeta.example wins.
is_deeply
    $ex->resolve_example( {}, { 'x-oaiMeta' => { example => { hi => 1 } } } ),
    { hi => 1 },
    'resolve_example: schema.x-oaiMeta.example wins (priority 1)';

# 2. schema.example wins when no x-oaiMeta.
is_deeply
    $ex->resolve_example( {}, { example => { fallback => 1 } } ),
    { fallback => 1 },
    'resolve_example: schema.example used (priority 2)';

# 3. Method-level x-oaiMeta.examples[0].response when schema has neither.
is_deeply
    $ex->resolve_example(
        { 'x-oaiMeta' => { examples => [ { response => { from_method => 1 } } ] } },
        { type => 'object' },
    ),
    { from_method => 1 },
    'resolve_example: method-level x-oaiMeta wins over synthesis (priority 3)';

# 4. Synthesis fallback when none of the above match.
my $thing = $spec->resolve_ref('#/components/schemas/Thing');
is_deeply
    $ex->resolve_example( {}, $thing ),
    { name => 'string', size => 10 },
    'resolve_example: synthesizes from schema as last resort (priority 4)';

done_testing;
```

- [ ] **Step 2: Run, verify fail**

Run: `prove -l devel/t/docgen-example.t`
Expected: FAIL.

- [ ] **Step 3: Implement per design §Examples (lines 194-259)**

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Example.pm`:

```perl
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
        spec    => $args{spec},
        max_depth => $args{max_depth} // 4,
    }, $class;
}

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
        $s += 1000 if exists $v->{example} || exists( $v->{'x-oaiMeta'}{example} // undef );
        $s += 10   if exists $v->{enum};
        $s += 10   if exists $v->{default};
        $s +=  1 * keys %{ $v->{properties} // {} };
        return $s;
    };
    my ($best) = sort { $score->($b) <=> $score->($a) } @$variants;
    return $best // $variants->[0];
}

1;
```

- [ ] **Step 4: Run, verify pass**

Run: `prove -l devel/t/docgen-example.t`
Expected: PASS. Adjust the test expectations for `format_example` if `JSON::PP`'s `pretty` output uses different spacing than the test expects — the goal is canonical, deterministic encoding, not a specific byte pattern.

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Example.pm devel/t/docgen-example.t
git commit -m "Add DocGen::Example: format + synthesize with oneOf scoring, cycle detection"
```

### Task 2.5: `DocGen::Schema` — schema walker → property records

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Schema.pm`
- Create: `devel/t/docgen-schema.t`

- [ ] **Step 1: Write the failing test**

`devel/t/docgen-schema.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Schema;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $walker = OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec );

my $result = $walker->walk( $spec->resolve_ref('#/components/schemas/Thing') );

# Returns { properties => [...], referenced_components => { Name => $schema } }
isa_ok $result, 'HASH';
ok ref $result->{properties} eq 'ARRAY';

my %by_name = map { $_->{name} => $_ } @{ $result->{properties} };
is $by_name{name}{type},     'string',  'name property type';
is $by_name{size}{type},     'integer', 'size property type';
is $by_name{size}{default},  10,        'size default';

# A schema with a $ref to a named component records the component for the
# SCHEMAS section but does not recurse inline.
my $wrapper = { type => 'object', properties => { thing => { '$ref' => '#/components/schemas/Thing' } } };
my $r2 = $walker->walk($wrapper);
ok exists $r2->{referenced_components}{Thing}, 'ref to named component noted';
my ($thing_prop) = grep { $_->{name} eq 'thing' } @{ $r2->{properties} };
is $thing_prop->{ref_target}, 'Thing', 'inline property notes the ref target';

# Truncation: nested anonymous objects beyond max_depth get a flag.
# Build a 5-deep object: outer.l1.l2.l3.l4.l5 where max_depth=4.
my $deep_leaf = { type => 'object', properties => { leaf => { type => 'string' } } };
my $deep = { type => 'object', properties => {} };
my $cur  = $deep;
for my $level ( 1 .. 5 ) {
    $cur->{properties}{"l$level"} = { type => 'object', properties => {} };
    $cur = $cur->{properties}{"l$level"};
}
$cur->{properties}{leaf} = { type => 'string' };

my $r3 = $walker->walk($deep);
# Drill into the result to find the first 'truncated' record.
sub find_truncated {
    my ($props) = @_;
    for my $p (@$props) {
        return $p if $p->{truncated};
        if ( $p->{children} ) {
            my $hit = find_truncated( $p->{children} );
            return $hit if $hit;
        }
    }
    return undef;
}
my $trunc = find_truncated( $r3->{properties} );
ok defined $trunc, 'truncated property flagged at depth 4';
is $trunc->{type}, 'object', 'truncated property keeps its type';

done_testing;
```

- [ ] **Step 2: Run, verify fail**

Run: `prove -l devel/t/docgen-schema.t`
Expected: FAIL.

- [ ] **Step 3: Implement `DocGen::Schema`**

Per design §"Per-path POD structure" and §"$ref handling". Skeleton:

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Schema.pm`:

```perl
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
```

- [ ] **Step 4: Run, verify pass**

Run: `prove -l devel/t/docgen-schema.t`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Schema.pm devel/t/docgen-schema.t
git commit -m "Add DocGen::Schema: schema walker producing property records + ref index"
```

### Task 2.6: `DocGen::Render::Path` — per-path POD emitter

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/Path.pm`
- Create: `devel/t/docgen-render-path.t`

- [ ] **Step 1: Write the failing test**

`devel/t/docgen-render-path.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use Pod::Checker;

use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;
use OpenAPI::Client::OpenAI::DocGen::Schema;
use OpenAPI::Client::OpenAI::DocGen::Render::Path;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::Path->new(
    spec    => $spec,
    example => OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec ),
    schema  => OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec ),
);

my $pod = $renderer->render('/things');

# Structural checks.
like $pod, qr/^=encoding utf8/m, 'encoding';
like $pod, qr/=head1 NAME/,      'NAME section';
like $pod, qr/=head2 POST \/things/, 'method header';
like $pod, qr/=head3 createThing/, 'operationId head3';
like $pod, qr/\$client->create_thing/, 'snake_case in synopsis';
like $pod, qr/=head1 SCHEMAS/, 'SCHEMAS section (Thing is referenced)';
like $pod, qr/=head2 Thing/, 'Thing component documented under SCHEMAS';

# No empty =over/=back blocks.
unlike $pod, qr/=over[^\S\n]*\n\s*=back/, 'no empty over/back';

# podchecker: zero errors AND zero warnings on this synthetic spec.
my $checker = Pod::Checker->new( -warnings => 1 );
open my $fh, '<', \$pod;
$checker->parse_from_filehandle($fh);
is $checker->num_errors, 0, 'no podchecker errors';

done_testing;
```

- [ ] **Step 2: Run, verify fail**

Run: `prove -l devel/t/docgen-render-path.t`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `DocGen::Render::Path`**

Per design §"Per-path POD structure" (lines 102-160). Skeleton (the actual emitter is line-by-line `push @lines, ...` per the design's no-template rule):

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/Path.pm`:

```perl
package OpenAPI::Client::OpenAI::DocGen::Render::Path;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use JSON::PP;
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

my $JSON = JSON::PP->new->canonical->pretty;

sub new ( $class, %args ) {
    return bless {
        spec    => $args{spec},
        example => $args{example},
        schema  => $args{schema},
    }, $class;
}

sub render ( $self, $path ) {
    my $path_data = $self->{spec}->paths->{$path};
    my $sanitized = _sanitize_path($path);
    my @lines;

    my $emit = sub { push @lines, @_ };
    my $blank = sub { push @lines, '' };

    $emit->('=encoding utf8');
    $blank->();
    $emit->('=head1 NAME');
    $blank->();
    $emit->("OpenAPI::Client::OpenAI::Path::$sanitized - Documentation for the $path path.");
    $blank->();

    if ( my $desc = $path_data->{description} ) {
        $emit->('=head1 DESCRIPTION');
        $blank->();
        $emit->( md_to_pod($desc) );
        $blank->();
    }

    $emit->('=head1 OPERATIONS');
    $blank->();

    my %all_components;
    for my $method ( sort grep { !/^(?:description|parameters)$/ } keys %$path_data ) {
        my $method_data = $path_data->{$method};
        my $op_id       = $method_data->{operationId} // next;
        my $snake       = to_snake_case($op_id);
        my $verb        = uc $method;

        $emit->("=head2 $verb $path");
        $blank->();
        $emit->("=head3 $op_id");
        $blank->();
        $emit->("  \$client->$snake({");
        $emit->("      body => { ... },");
        $emit->("  });");
        $blank->();

        if ( my $summary = $method_data->{summary} ) {
            $emit->( md_to_pod($summary) );
            $blank->();
        }
        if ( my $desc = $method_data->{description} ) {
            $emit->( md_to_pod($desc) );
            $blank->();
        }

        $self->_emit_parameters( $emit, $blank, $method_data, \%all_components );
        $self->_emit_request_body( $emit, $blank, $method_data, \%all_components );
        $self->_emit_responses( $emit, $blank, $method_data, \%all_components );
    }

    $self->_emit_schemas_section( $emit, $blank, \%all_components );

    $emit->('=head1 SEE ALSO');
    $blank->();
    $emit->('L<OpenAPI::Client::OpenAI::Path>');
    $blank->();
    $emit->('=head1 COPYRIGHT AND LICENSE');
    $blank->();
    my $year = (localtime)[5] + 1900;
    $emit->("Copyright (C) 2023-$year by Nelson Ferraz");
    $blank->();
    $emit->('This library is free software; you can redistribute it and/or modify');
    $emit->('it under the same terms as Perl itself, either Perl version 5.14.0 or,');
    $emit->('at your option, any later version of Perl 5 you may have available.');
    $blank->();
    $emit->('=cut');

    return join( "\n", @lines ) . "\n";
}

sub _emit_parameters ( $self, $emit, $blank, $method_data, $components ) {
    my $params = $method_data->{parameters} or return;
    return unless @$params;

    $emit->('=head4 Path/query parameters');
    $blank->();
    $emit->('=over');
    $blank->();
    for my $p (@$params) {
        my $required = $p->{required} ? 'required' : 'optional';
        my $where    = $p->{in};
        my $type     = $p->{schema}{type} // 'string';
        my $desc     = $p->{description} ? ' — ' . md_to_pod($p->{description}) : '';
        $emit->("=item * C<$p->{name}> (in $where, $required, $type)$desc");
        $blank->();
        if ( $p->{schema}{enum} ) {
            $emit->('Allowed values: ' . join(', ', @{ $p->{schema}{enum} }));
            $blank->();
        }
        if ( exists $p->{schema}{default} ) {
            $emit->("Default: $p->{schema}{default}");
            $blank->();
        }
    }
    $emit->('=back');
    $blank->();
}

sub _emit_request_body ( $self, $emit, $blank, $method_data, $components ) {
    my $body = $method_data->{requestBody} or return;
    my $content = $body->{content} or return;

    for my $ct ( sort keys %$content ) {
        my $schema = $content->{$ct}{schema} or next;
        $emit->('=head4 Request body');
        $blank->();
        $emit->("Content-Type: $ct");
        $blank->();
        $self->_emit_property_block( $emit, $blank, $schema, $components );
        $self->_emit_example_block( $emit, $blank, $method_data, $schema );
    }
}

sub _emit_responses ( $self, $emit, $blank, $method_data, $components ) {
    my $responses = $method_data->{responses} or return;
    $emit->('=head4 Responses');
    $blank->();
    for my $code ( sort keys %$responses ) {
        my $r = $responses->{$code};
        my $desc = $r->{description} // '';
        $emit->("B<$code — " . md_to_pod($desc) . '>');
        $blank->();
        my $content = $r->{content} or next;
        for my $ct ( sort keys %$content ) {
            my $schema = $content->{$ct}{schema} or next;
            $emit->("Content-Type: $ct");
            $blank->();
            $self->_emit_property_block( $emit, $blank, $schema, $components );
            $self->_emit_example_block( $emit, $blank, $method_data, $schema );
        }
    }
}

sub _emit_property_block ( $self, $emit, $blank, $schema, $components ) {
    my $result = $self->{schema}->walk($schema);
    %$components = ( %$components, %{ $result->{referenced_components} } );

    my @props = @{ $result->{properties} };
    return unless @props;

    $emit->('Properties:');
    $blank->();
    $emit->('=over');
    $blank->();
    for my $p (@props) {
        my $required = $p->{required} ? ', required' : '';
        my $type     = $p->{type};
        my $desc     = $p->{description} ? ' — ' . md_to_pod($p->{description}) : '';
        if ( $p->{ref_target} ) {
            $emit->("=item * C<$p->{name}> ($p->{ref_target}$required)$desc");
            $blank->();
            $emit->("See L</$p->{ref_target}> below for shape.");
            $blank->();
            next;
        }
        $emit->("=item * C<$p->{name}> ($type$required)$desc");
        $blank->();
        if ( $p->{truncated} ) {
            $emit->(
                'Nested shape omitted at depth 4; see the full spec at '
                . 'L<https://platform.openai.com/docs/api-reference>.'
            );
            $blank->();
            next;
        }
        if ( $p->{enum} ) {
            $emit->('Allowed values: ' . join(', ', @{ $p->{enum} }));
            $blank->();
        }
        if ( exists $p->{default} ) {
            $emit->("Default: $p->{default}");
            $blank->();
        }
    }
    $emit->('=back');
    $blank->();
}

sub _emit_example_block ( $self, $emit, $blank, $method_data, $schema ) {
    my $raw = $self->{example}->resolve_example( $method_data, $schema );
    return unless defined $raw;
    my $json = $self->{example}->format_example($raw) // return;
    $emit->('Example:');
    $blank->();
    for my $line ( split /\n/, $json ) {
        $emit->("    $line");
    }
    $blank->();
}

sub _emit_schemas_section ( $self, $emit, $blank, $components ) {
    return unless %$components;
    $emit->('=head1 SCHEMAS');
    $blank->();
    for my $name ( sort keys %$components ) {
        my $schema = $components->{$name};
        $emit->("=head2 $name");
        $blank->();
        my %scratch_components;
        $self->_emit_property_block( $emit, $blank, $schema, \%scratch_components );
        # Note: we intentionally do NOT recurse into transitively-referenced
        # components here; the design accepts this in exchange for self-contained
        # per-path files. If a Thing references a Widget, the Widget is named in
        # the property record but its shape lives in whatever path file uses it
        # directly.
    }
}

sub _sanitize_path ($path) {
    my $s = $path;
    $s =~ s{^/+}{};
    $s =~ s{[/{}]}{-}g;
    $s =~ s{-+$}{};
    $s =~ s{--+}{-}g;
    return $s;
}

1;
```

- [ ] **Step 4: Run, verify pass**

Run: `prove -l devel/t/docgen-render-path.t`
Expected: PASS. If `Pod::Checker` reports errors, inspect the generated POD (print `$pod` from the test) and fix the renderer — likely candidates are missing blank lines around `=over`/`=back` or unclosed `B<>`/`C<>` runs.

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/Path.pm devel/t/docgen-render-path.t
git commit -m "Add DocGen::Render::Path: per-path POD emitter (line-by-line, no templates)"
```

### Task 2.7: `DocGen::Render::PathIndex` — Path.pod emitter

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/PathIndex.pm`
- Create: `devel/t/docgen-render-pathindex.t`

- [ ] **Step 1: Write failing test**

`devel/t/docgen-render-pathindex.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::PathIndex->new( spec => $spec );

my $pod = $renderer->render;

like $pod, qr/=head1 NAME/, 'NAME section';
like $pod, qr/=head2 \/things/, 'path listed';
like $pod, qr/POST.*create_thing/, 'POST shows snake_case method';
like $pod, qr/L<OpenAPI::Client::OpenAI::Path::things>/, 'link to per-path POD';

done_testing;
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement per design §Indexes — `Path.pod (by URL)` (lines 327-339)**

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/PathIndex.pm`:

```perl
package OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use OpenAPI::Client::OpenAI::Naming qw(to_snake_case);
use OpenAPI::Client::OpenAI::DocGen::Markdown qw(md_to_pod);

sub new ( $class, %args ) { bless { spec => $args{spec} }, $class }

sub render ($self) {
    my @lines;
    push @lines, '=encoding utf8', '';
    push @lines, '=head1 NAME', '';
    push @lines, 'OpenAPI::Client::OpenAI::Path - Index of OpenAI API Paths', '';
    push @lines, '=head1 DESCRIPTION', '';
    push @lines, 'Index of paths in the OpenAI API; each links to its per-path documentation.', '';
    push @lines, '=head1 PATHS', '';

    my $paths = $self->{spec}->paths;
    for my $path ( sort keys %$paths ) {
        my $pdata = $paths->{$path};
        my $sanitized = _sanitize_path($path);

        push @lines, "=head2 $path", '';
        if ( my $desc = $pdata->{description} ) {
            push @lines, md_to_pod($desc), '';
        }
        push @lines, '=over', '';
        for my $method ( sort grep { !/^(?:description|parameters)$/ } keys %$pdata ) {
            my $md     = $pdata->{$method};
            my $verb   = uc $method;
            my $op     = $md->{operationId} // next;
            my $snake  = to_snake_case($op);
            my $summary = $md->{summary} // '';
            push @lines, "=item * C<$verb> $snake — " . md_to_pod($summary), '';
        }
        push @lines, '=back', '';
        push @lines, "See L<OpenAPI::Client::OpenAI::Path::$sanitized>.", '';
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
```

- [ ] **Step 4: Run, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/PathIndex.pm devel/t/docgen-render-pathindex.t
git commit -m "Add DocGen::Render::PathIndex: Path.pod emitter with snake_case method names"
```

### Task 2.8: `DocGen::Render::MethodIndex` — Methods.pod emitter

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/MethodIndex.pm`
- Create: `devel/t/docgen-render-methodindex.t`

- [ ] **Step 1: Write failing test**

`devel/t/docgen-render-methodindex.t`:

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../lib";
use Test::Most;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex;

my $spec = OpenAPI::Client::OpenAI::DocGen::Spec->load(
    "$FindBin::Bin/fixtures/tiny-spec.yaml"
);
my $r = OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex->new( spec => $spec );
my $pod = $r->render;

like $pod, qr/=head2 create_thing/, 'snake_case method head';
like $pod, qr/POST \/things/, 'verb + path';
like $pod, qr/operationId: createThing/, 'original operationId noted';
like $pod, qr/L<OpenAPI::Client::OpenAI::Path::things>/, 'link to per-path POD';

done_testing;
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement per design §Indexes — `Methods.pod` (lines 342-353)**

`devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/MethodIndex.pm`:

```perl
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
```

- [ ] **Step 4: Run, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen/Render/MethodIndex.pm devel/t/docgen-render-methodindex.t
git commit -m "Add DocGen::Render::MethodIndex: auto-generated Methods.pod by snake_case name"
```

### Task 2.9: `DocGen` orchestrator

**Files:**
- Create: `devel/lib/OpenAPI/Client/OpenAI/DocGen.pm`
- Create: `devel/t/docgen-orchestrator.t`

- [ ] **Step 1: Write failing test**

`devel/t/docgen-orchestrator.t`:

```perl
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
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement `DocGen` orchestrator**

`devel/lib/OpenAPI/Client/OpenAI/DocGen.pm`:

```perl
package OpenAPI::Client::OpenAI::DocGen;

use 5.026;
use strict;
use warnings;
use experimental 'signatures';
use Path::Tiny;
use OpenAPI::Client::OpenAI::DocGen::Spec;
use OpenAPI::Client::OpenAI::DocGen::Example;
use OpenAPI::Client::OpenAI::DocGen::Schema;
use OpenAPI::Client::OpenAI::DocGen::Render::Path;
use OpenAPI::Client::OpenAI::DocGen::Render::PathIndex;
use OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex;

sub new ( $class, %args ) {
    return bless {
        spec_file  => $args{spec_file},
        output_dir => path( $args{output_dir} ),
    }, $class;
}

sub run ($self) {
    my $spec    = OpenAPI::Client::OpenAI::DocGen::Spec->load( $self->{spec_file} );
    my $example = OpenAPI::Client::OpenAI::DocGen::Example->new( spec => $spec );
    my $schema  = OpenAPI::Client::OpenAI::DocGen::Schema->new( spec => $spec );
    my $renderer = OpenAPI::Client::OpenAI::DocGen::Render::Path->new(
        spec => $spec, example => $example, schema => $schema,
    );

    my $base = $self->{output_dir}->child('lib/OpenAPI/Client/OpenAI');
    $base->child('Path')->mkpath;

    for my $path ( sort keys %{ $spec->paths } ) {
        my $sanitized = _sanitize_path($path);
        my $pod = $renderer->render($path);
        $base->child("Path/$sanitized.pod")->spew_utf8($pod);
    }

    my $path_index = OpenAPI::Client::OpenAI::DocGen::Render::PathIndex->new( spec => $spec );
    $base->child('Path.pod')->spew_utf8( $path_index->render );

    my $method_index = OpenAPI::Client::OpenAI::DocGen::Render::MethodIndex->new( spec => $spec );
    $base->child('Methods.pod')->spew_utf8( $method_index->render );
}

sub _sanitize_path ($path) {
    my $s = $path;
    $s =~ s{^/+}{};
    $s =~ s{[/{}]}{-}g;
    $s =~ s{-+$}{};
    $s =~ s{--+}{-}g;
    return $s;
}

1;
```

- [ ] **Step 4: Run, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add devel/lib/OpenAPI/Client/OpenAI/DocGen.pm devel/t/docgen-orchestrator.t
git commit -m "Add DocGen orchestrator: wires Spec/Example/Schema/Render and writes files"
```

**Phase 2 gate:** `RELEASE_TESTING=1 make test` passes (now exercises 9 new unit-test files under `devel/t/`). Old `build_docs.pl` still produces the existing output unchanged. `git diff lib/OpenAPI/Client/OpenAI/Path*` is empty.

---

## Phase 3 — Wire DocGen in, regenerate (Commit 3)

**Why next:** Switch `build_docs.pl` to use `DocGen`, regenerate every `.pod` file, add the integration test. This commit is large (~180 file diff) but a single logical change.

### Task 3.1: Rewrite `devel/build_docs.pl` as a thin CLI

**Files:**
- Modify: `devel/build_docs.pl` (replace entire file)

- [ ] **Step 1: Replace `devel/build_docs.pl`**

```perl
#!/usr/bin/env perl
use 5.026;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";

use Path::Tiny;
use OpenAPI::Client::OpenAI::DocGen;

my $spec_file  = $ARGV[0] // 'share/openapi.yaml';
my $output_dir = $ARGV[1] // '.';

OpenAPI::Client::OpenAI::DocGen->new(
    spec_file  => $spec_file,
    output_dir => $output_dir,
)->run;

say "Wrote POD under $output_dir/lib/OpenAPI/Client/OpenAI/";
```

That's the whole script — the orchestrator does the work.

- [ ] **Step 2: Sanity-run against a temp dir**

```bash
mkdir -p /tmp/docgen-check
perl devel/build_docs.pl share/openapi.yaml /tmp/docgen-check
ls /tmp/docgen-check/lib/OpenAPI/Client/OpenAI/Path/ | head
ls /tmp/docgen-check/lib/OpenAPI/Client/OpenAI/
```

Expected: lots of `.pod` files under `Path/`, plus `Path.pod` and `Methods.pod`.

If anything dies, the error message identifies the culprit module — debug there before moving on.

- [ ] **Step 3: Do NOT commit yet** — Task 3.2 lands the integration test first so the regen in Task 3.3 is gated.

### Task 3.2: Integration test + `podchecker` baseline

**Files:**
- Create: `devel/t/docgen-integration.t`
- Create: `devel/t/podcheck-baseline.txt` (single integer)

- [ ] **Step 1: Establish the baseline**

```bash
perl devel/build_docs.pl share/openapi.yaml /tmp/docgen-check
perl -MPod::Checker -e '
    use File::Find;
    my $total_warn = 0;
    find( sub {
        return unless /\.pod$/;
        my $c = Pod::Checker->new( -warnings => 1 );
        $c->parse_from_file($File::Find::name, \*STDERR);
        $total_warn += $c->num_warnings // 0;
        die "ERROR in $File::Find::name\n" if $c->num_errors;
    }, "/tmp/docgen-check/lib" );
    print "TOTAL WARNINGS: $total_warn\n";
' 2>/dev/null
```

Note the printed total. Write that integer to `devel/t/podcheck-baseline.txt` (single line, no trailing whitespace beyond a final newline).

Goal is to drive this to zero; the baseline records the ceiling so regressions surface without chasing every cosmetic Pod::Checker opinion.

- [ ] **Step 2: Write the integration test**

`devel/t/docgen-integration.t`:

```perl
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
    open my $null, '>', \my $sink;
    $c->parse_from_file( $file, $null );
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

done_testing;
```

- [ ] **Step 3: Run the integration test**

```bash
prove -l devel/t/docgen-integration.t
```

Expected: PASS. If errors are reported, fix the renderer (errors must be zero unconditionally). If warnings exceed baseline, the test prints the per-file diag — likely some `=over`/`=back` or unclosed inline run snuck in; fix and re-run.

- [ ] **Step 4: Do NOT commit yet** — bundle with Task 3.3.

### Task 3.3: Regenerate all POD + update MANIFEST

- [ ] **Step 1: Regenerate in place**

```bash
perl devel/build_docs.pl share/openapi.yaml .
```

This writes (and overwrites) every `.pod` under `lib/OpenAPI/Client/OpenAI/`.

- [ ] **Step 2: Regenerate MANIFEST**

```bash
make manifest
```

Expected: any newly-generated `.pod` files appear in `MANIFEST`. Any that no longer exist (e.g. retired paths) are removed.

- [ ] **Step 3: Run the full test suite**

```bash
RELEASE_TESTING=1 make test
```

Expected: PASS. Including the integration test, all `devel/t/` units, all existing `t/*.t`.

- [ ] **Step 4: Visual spot-check a handful of regenerated files**

Look at three representative files:
- `lib/OpenAPI/Client/OpenAI/Path/chat-completions.pod` — the canonical example.
- `lib/OpenAPI/Client/OpenAI/Path/realtime-calls-call_id-refer.pod` — previously had the invalid kebab-case Perl example.
- `lib/OpenAPI/Client/OpenAI/Methods.pod` — newly auto-generated.

Confirm:
- No `$client->some-kebab-thing(...)` (would be invalid Perl).
- No empty `=over\n=back` blocks.
- No 80-character `=` rules in the middle of POD.
- Snake_case method shown in the synopsis-style code block at the top of each operation.
- Where deeply-nested anonymous objects exist, the property is followed by the marker line `Nested shape omitted at depth 4; see the full spec at L<https://platform.openai.com/docs/api-reference>.` (search for `Nested shape omitted` across the regenerated files).
- For operations that have `x-oaiMeta.examples` at the method level (grep `share/openapi.yaml` for `x-oaiMeta` to spot a few), the rendered `Example:` block matches the curated response rather than a synthesized fallback.

- [ ] **Step 5: Commit everything in Phase 3 together**

```bash
git add devel/build_docs.pl devel/t/docgen-integration.t devel/t/podcheck-baseline.txt \
        MANIFEST lib/OpenAPI/Client/OpenAI/Path.pod lib/OpenAPI/Client/OpenAI/Methods.pod \
        lib/OpenAPI/Client/OpenAI/Path/
git commit -m "Switch build_docs to DocGen; regenerate all POD with integration test"
```

(Yes, the diff is enormous. That's expected — the commit message names *one* change ("the generator is different; here's its output") so reviewers know what they're scanning for.)

**Phase 3 gate:** `RELEASE_TESTING=1 make test` passes. Integration test passes (zero errors; warnings ≤ baseline).

---

## Phase 4 — Delete old code (Commit 4)

**Why last:** Keeps Phase 3 reviewable by isolating *new code* from *removed code*. Now that DocGen is wired in and tested, the old helpers in the original `build_docs.pl` are dead — except they were already replaced in Phase 3.1. This phase removes the now-unused build dependencies.

### Task 4.1: Trim `Makefile.PL` build dependencies

**Files:**
- Modify: `Makefile.PL`

- [ ] **Step 1: Identify dependencies the new code no longer uses**

The old script used `Template`, `Markdown::Pod`, `Text::Wrap`, `Clone`, `File::Slurp`. The new `DocGen` modules use:

- `YAML::XS` — still needed (load spec).
- `Path::Tiny` — still needed.
- `JSON::PP` — still needed (core; declared in TEST_REQUIRES, that's fine).
- Nothing else from the original list.

Remove from `BUILD_REQUIRES` in `Makefile.PL`:

```perl
        'File::Slurp'          => '0',
        'Text::Wrap'           => '0',
        'Markdown::Pod'        => '0',
        'Feature::Compat::Try' => '0',
        'Perl::Tidy'           => '0',
        'Markdown::Pod'        => '0',   # duplicate entry in current file
        'Template'             => '0',
```

(Keep `YAML::XS` and `Path::Tiny`. Confirm `Perl::Tidy` isn't used elsewhere — it appears in `TEST_REQUIRES` too; the `TEST_REQUIRES` entry stays as-is unless tests prove not to need it.)

- [ ] **Step 2: Verify by clean rebuild**

```bash
make realclean
perl Makefile.PL && make && RELEASE_TESTING=1 make test
```

Expected: PASS. If any test or build step fails citing one of the removed modules, that module is still in use — restore it and find the actual offender.

- [ ] **Step 3: Confirm no stray `use Markdown::Pod`, `use Template`, etc. in the tree**

```bash
grep -rn "use Markdown::Pod\|use Template\|use Text::Wrap\|use File::Slurp" lib/ devel/lib/ devel/build_docs.pl t/
```

Expected: no matches (or only matches in files unrelated to the docgen).

- [ ] **Step 4: Commit**

```bash
git add Makefile.PL
git commit -m "Drop Markdown::Pod, Template, Text::Wrap, File::Slurp from build deps"
```

### Task 4.2: Update `Changes` for the docgen rewrite

**Files:**
- Modify: `Changes`

- [ ] **Step 1: Expand the `0.27 (dev)` entry**

Append below the snake_case bullet added in Task 1.3:

```
        - Documentation generator rewrite: per-path POD is now produced by
          a modular generator under devel/lib/OpenAPI/Client/OpenAI/DocGen*.
          Notable fixes:
            * snake_case Perl method in every code example (previously,
              kebab-case operationIds produced uncompilable examples).
            * Methods.pod is now auto-generated (alphabetical, ~5 lines
              per method), replacing a stale hand-maintained file.
            * JSON examples are normalized (no more nested stringified
              JSON) and oneOf/anyOf variants are scored by informativeness
              instead of YAML order.
            * Markdown horizontal rules no longer leak 80-character `='
              artifacts into the POD.
            * Build dependencies dropped: Markdown::Pod, Template,
              Text::Wrap, File::Slurp.
```

- [ ] **Step 2: Commit**

```bash
git add Changes
git commit -m "Changes: document the docgen rewrite and its user-visible fixes"
```

**Phase 4 gate:** `RELEASE_TESTING=1 make test` passes. `make dist` produces a tarball that does not contain `devel/lib/` or `devel/t/`.

---

## Release (not part of these four commits, but the natural next step)

- [ ] Bump `our $VERSION` in `lib/OpenAPI/Client/OpenAI.pm` from `0.26` to `0.27`.
- [ ] Replace `0.27    (dev)` in `Changes` with `0.27    YYYY-MM-DD` (today).
- [ ] Run `devel/rebuild` once more to confirm everything still passes from clean.
- [ ] Tag and release per `devel/tag-release` (existing process).

---

## What this plan deliberately does *not* do

- Rename `Path.pod` / `Path/*.pod` layout — out of scope per design §"Out of scope".
- Emit Markdown alongside POD — out of scope; `pod2markdown` post-processes.
- Add a per-path CLI to regenerate one file at a time — out of scope.

## When something goes off-script

The single most useful debugging command after any task fails:

```bash
perl devel/build_docs.pl share/openapi.yaml /tmp/dump
diff -r lib/OpenAPI/Client/OpenAI/Path /tmp/dump/lib/OpenAPI/Client/OpenAI/Path | less
```

That shows precisely what the new generator changes about a given file, and is the fastest way to spot regressions during phases 2 and 3.
