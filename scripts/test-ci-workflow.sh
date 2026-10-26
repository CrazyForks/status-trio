#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  verify = workflow.fetch("jobs").fetch("verify")
  steps = verify.fetch("steps")
  preflight = steps.index { |s| s["name"] == "Run static release preflight" } or abort "missing early static preflight"
  tests = steps.index { |s| s["name"] == "Run tests" } or abort "missing tests"
  native = steps.index { |s| s["name"] == "Run native and release-contract tests" } or abort "missing native"
  abort "static checks must precede Swift tests" unless preflight < tests && tests < native
  static = steps[preflight].fetch("run")
  ["bash -n", "check-forbidden-patterns.sh", "check-release-workflow-policy.sh",
   "test-release-workflow-policy.sh", "validate-appcast-notes.sh"].each do |required|
    abort "missing preflight #{required}" unless static.include?(required)
  end
  test = steps[tests].fetch("run")
  abort "missing diagnostic test wrapper" unless test.include?(%q{ci-run-stage.sh" tests bash scripts/test.sh})
  abort "unconditional bundle dumps remain" if test.include?("find .build") || test.include?("head -n")
  scripts = steps.map { |s| s["run"] }.compact.join("\n")
  ["bash scripts/test.sh", %q{bash "$CI_TOOLS_ROOT/scripts/test-release-workflow-policy.sh"}].each do |cmd|
    abort "duplicate or missing #{cmd}" unless scripts.scan(cmd).size == 1
  end
  summary = steps.find { |s| s["name"] == "Summarize verify diagnostics" } or abort "missing summary"
  abort "summary must run after failure" unless summary.fetch("if") == "always()"
  upload = steps.find { |s| s["name"] == "Upload verify diagnostics" } or abort "missing verify logs"
  abort "logs must survive failure" unless upload.fetch("if") == "always()"
  abort "broad diagnostic upload" unless upload.fetch("with").fetch("path") == ".build/ci-logs/"
  abort "failure suppression" if steps.any? { |s| s["continue-on-error"] }
  tooling = verify.fetch("env").fetch("CI_TOOLS_ROOT")
  abort "recovery must use trusted diagnostics for older candidates" unless
    tooling.include?("inputs.package_run_id") && tooling.include?("release-tools")
  ["test-ci-workflow.sh", "test-ci-diagnostics.sh", "test-build-timing.sh",
   "test-mobile-battery-build-cache.sh", "check-release-workflow-policy.sh",
   "test-release-workflow-policy.sh"].each do |script|
    abort "old recovery candidate cannot supply #{script}" unless
      scripts.include?(%Q{"$CI_TOOLS_ROOT/scripts/#{script}"})
  end
  package = workflow.fetch("jobs").fetch("package").fetch("steps")
  key_step = package.find { |s| s["id"] == "native-cache-keys" } or abort "missing cache key step"
  %w[arm64 x86_64].each do |arch|
    abort "cache key #{arch} is not written to Actions outputs" unless
      key_step.fetch("run").include?(%Q{--github-output "$GITHUB_OUTPUT" --output-name key_#{arch}})
  end
' "$ROOT/.github/workflows/release.yml"
echo "CI workflow: early static checks, strict test wrapper and failure diagnostics passed"
