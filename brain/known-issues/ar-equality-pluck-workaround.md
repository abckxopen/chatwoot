# AR `==` Returning False on Equal Records — Zeitwerk Reload Race

**Status:** ✅ RESOLVED 2026-05-07 (commit b4584ad5)
**First seen:** 2026-05-07 PR #9 (slice 2 Stages)
**Fully resolved:** 2026-05-07 PR #12 (slice 5 Activities)

## Symptom

In CI parallel test partition `backend-tests (16, 0)`, RSpec specs comparing ActiveRecord records via `eq([record1, record2])` or `contain_exactly(record)` failed deterministically:

- `expected collection contained: [#<Holding::Crm::X id: N, ...>]`
- `actual collection contained:   [#<Holding::Crm::X id: N, ...>]`
- `the missing elements were:     [#<Holding::Crm::X id: N, ...>]`
- `the extra elements were:       [#<Holding::Crm::X id: N, ...>]`

Same id, same FQN, but `==` returned false. Same symptom in `spec/lib/safe_fetch_spec.rb`: `raise_error(SafeFetch::InvalidUrlError)` failed with `expected SafeFetch::InvalidUrlError, got SafeFetch::InvalidUrlError`.

## Root Cause

`config/environments/test.rb` sets:
```ruby
config.cache_classes = false
config.eager_load = false
```

Combined with Zeitwerk autoload, this means classes load on first reference and **can be reloaded between specs**. When reload happened mid-suite, two `Class` objects existed for the same FQN (e.g. `Holding::Crm::Pipeline` instance loaded for spec A vs reloaded constant referenced from spec B). RSpec's `eq` and `is_a?` matchers compare by class identity (`object_id`), so equal-by-name-and-id records returned false.

The CI parallel partition layout (16 shards) determined which specs landed together in the same process. As Phase 1 added more spec files, partition 0's contents shifted enough to expose this race deterministically.

## Fix

Single fork-local file: `spec/support/abckxopen_eager_load.rb`:

```ruby
RSpec.configure do |config|
  config.before(:suite) do
    Rails.application.eager_load!
  end
end
```

Auto-required by `spec/rails_helper.rb` line 30. Pre-loads every autoloadable class at suite boot — single `Class` object per FQN for the entire run. ~5s extra at boot, no upstream cherry-pick conflict (new file, fork-local naming prefix).

Upstream chatwoot has the same root cause but doesn't trigger the reload race in their default partition layout. Upstream issue same-flavor: ecdeb891 (#14139) was a partial fix at the spec-pinning level.

## What got reverted after the fix

- `lib/safe_fetch.rb` defensive `require_relative` inside method (commit 72caba11) — redundant under eager_load, would have created cherry-pick conflict.
- `.pluck(:id)` workarounds in pipeline_spec / opportunity_spec / activity_spec — back to idiomatic `eq([record])` / `contain_exactly(record)`.

## Postmortem value

The investigation hypotheses + diagnostic recipe (TracePoint, `--seed N` bisect, `class.object_id` check) remain useful for any future "same FQN, different Class" symptom. Not deleting this doc — keeping as reference for the next dev hitting a similar Zeitwerk surprise.

## Anchor commits

- `d54705a2` (slice 2): first `.pluck` workaround in pipeline_spec
- `4d358e0a` (slice 3): same in opportunity_spec
- `c18909cc` (slice 5): same in activity_spec
- `72caba11` (slice 5): lib/safe_fetch.rb defensive require
- `b4584ad5` (slice 5): root-cause fix via spec/support/abckxopen_eager_load.rb
- `<this commit>` (slice 5): clean-up — workarounds reverted, brain doc marked RESOLVED
