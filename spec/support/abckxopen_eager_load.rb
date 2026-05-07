# [2026-05-07 abckxopen-fork] Force eager-load classes at RSpec suite start.
#
# Why:
# config/environments/test.rb sets `eager_load = false` and `cache_classes = false`,
# which means Zeitwerk autoload kicks in on first reference and may reload
# classes between specs (or between rspec parallel partitions). When this
# happens, two Class objects exist for the same FQN — old instances pass
# `is_a?` checks against the OLD class only, while spec matchers like
# `raise_error(SafeFetch::InvalidUrlError)` resolve against the NEW one.
# Result: deterministic CI failures in some partition layouts.
#
# Symptoms observed:
# - spec/lib/safe_fetch_spec.rb: 13 failures `expected/actual same FQN`
# - spec/models/holding/crm/{pipeline,opportunity,activity}_spec.rb:
#   `eq([record])` / `contain_exactly(record)` returning false on equal records.
# - Brain doc: brain/known-issues/ar-equality-pluck-workaround.md
#
# Fix: pre-load every autoloadable class once at suite boot. Single-class-object
# guaranteed for the run. ~5s extra at boot. Only affects test env.
#
# Upstream issue same-flavor: ecdeb891 (#14139) only patched part of it.
# This support file is fork-local — zero upstream cherry-pick conflict.

RSpec.configure do |config|
  config.before(:suite) do
    Rails.application.eager_load!
  end
end
