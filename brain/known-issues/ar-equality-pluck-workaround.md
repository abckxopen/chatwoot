# AR `==` Returning False on Equal Records — Pluck Workaround

**Status:** P1 — investigate before slice 4 (Opportunities) lands or risk drift
**First seen:** 2026-05-07 PR #9 (slice 2 Stages)
**Reaperition:** 2026-05-07 PR #10 (slice 3 Companies)

## Symptom

In CI parallel test partition `backend-tests (16, 0)`, RSpec specs that compare ActiveRecord records via `eq([record1, record2])` or `contain_exactly(record)` fail deterministically with:

- `expected collection contained: [#<Holding::Crm::X id: N, ...>]`
- `actual collection contained:    [#<Holding::Crm::X id: N, ...>]`
- `the missing elements were:      [#<Holding::Crm::X id: N, ...>]`
- `the extra elements were:        [#<Holding::Crm::X id: N, ...>]`

Same id, same class string, same attributes — yet `==` returns false. RSpec's `eq` and `contain_exactly` matchers fail because they use `==` for comparison.

## Affected files

- `spec/models/holding/crm/pipeline_spec.rb` — slice 2 first hit
  - Line 50 (`#defaults_first` scope test)
  - Line 118 (tenancy isolation test)
- `spec/models/holding/crm/opportunity_spec.rb` — slice 3 reapparition
  - Line 33 (`#active` scope)
  - Line 37 (`#discarded` scope)
  - Line 143 (tenancy isolation)

## Workaround applied

Replace record comparison with id comparison + `.pluck(:id)`:

```ruby
# Before
expect(described_class.where(account_id: a.id)).to contain_exactly(record_a)

# After
expect(described_class.where(account_id: a.id).pluck(:id)).to contain_exactly(record_a.id)
```

`.pluck(:id)` is also a small efficiency win (`SELECT id` only, doesn't materialize records). Same pattern is used elsewhere in chatwoot (account_spec.rb, hook_spec.rb).

## Hypotheses (untested)

1. **Autoload pollution between specs in same partition.** RSpec random order means the new `crm_*_controller_spec.rb` files might be running before the affected model specs and leaving some constant resolution state divergent. AR `==` is `instance_of?(self.class) && id == other.id` — if `self.class` resolves to a different Class object between the local create and the relation-loaded record, `instance_of?` returns false. With Zeitwerk and `eager_load = true` in test env, this should NOT happen — but something is triggering it.
2. **Class reloading within RSpec process.** Some test setup might be calling `Object.send(:remove_const, ...)` and re-autoloading. We don't do this directly but a gem might.
3. **Spring / class_eval interaction.** Chatwoot uses Spring in dev but specs run without it. Verify in CI.
4. **Rails 7.1 / Ruby 3.4 specific regression.** Less likely — would affect every chatwoot project, not just our fork.

## Investigation steps (when this gets prioritized)

1. **Reproduce in isolation:** `bundle exec rspec spec/models/holding/crm/pipeline_spec.rb` standalone on the failing SHA. If it passes, it IS test-order pollution.
2. **Bisect by adding diagnostic puts:**
   ```ruby
   puts "expected.class.object_id = #{record_a.class.object_id}"
   puts "actual.class.object_id   = #{result.first.class.object_id}"
   ```
   If `object_id` differs, we have class duplication (Zeitwerk reload bug confirmed).
3. **Run with `--seed N`** to find the spec ordering that triggers pollution.
4. **Check `Spring.quiet` / `Spring.disable!`** in spec setup — if Spring is sneaking in.
5. **Audit constants resolution** during the test run with `TracePoint.new(:class)` to see if `Holding::Crm::Pipeline` ever gets re-defined.

## Exit criteria for removing the workaround

When the root cause is identified and fixed:
- All `.pluck(:id)` calls anchored with this issue note can revert to `eq([record])` / `contain_exactly(record)`.
- This brain doc updated to "RESOLVED" with root cause + fix description.
- Pattern stops appearing in slice 4+ specs.

## Anchors in code

Each occurrence in spec files has an inline anchor (`# [2026-05-07] Comparar por id em vez de record. ...`) that cross-references this doc. When investigating, search for `Comparar por id` to find all sites.

## Related

- Initial slice 2 commit: `d54705a` (workaround) + `87777b9` (anchor honesty)
- Slice 3 commit: `4d358e0` (workaround applied to opportunity_spec)
- Pre-merge simplify pass agents flagged this consistently as "real bug, not flake"
