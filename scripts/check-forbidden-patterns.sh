#!/usr/bin/env bash
# Fails when an actor-isolated method is passed as a function value.
#
# AGENTS.md: "Do not pass actor-isolated methods directly as function values.
# Use an explicit closure instead." docs/swift-ci-compatibility.md records CI
# run 34758026894, where `Binding.set: localization.setPreference` crashed
# IRGen on the Swift 6.1.2 release toolchain; the documented remedy is the
# explicit closure this script enforces.
#
# Detection rule, in this order:
#   1. Collect function-value positions: argument labels
#      (`action:`/`get:`/`set:`/`using:`/`block:`, plus the `request*:` and
#      `open*:` families this repo uses for its action callbacks) and the
#      `.map/.compactMap/.filter/.forEach/.sink/.assign` operators, plus any
#      `.callAsFunction` reference.
#   2. Drop anything that is already a closure (`{`), a call (`(`), a keypath
#      (`\.`), or a library initializer reference (`<Type>.init`). These stay in
#      `--list` under the token that was captured (`URL.init`), so a reader can
#      see they were considered instead of a second anonymous `external`.
#   3. A remaining bare identifier whose last component is declared as a
#      zero-argument `func <name>()` anywhere under Sources/ is a VIOLATION
#      unless it is in ALLOWED below, or is a forwarded closure value.
#   4. Anything else is `external` and is reported by --list but never fails.
#
# The declaration lookup fails closed on overloads: one zero-argument
# declaration anywhere under Sources/ is enough, so adding an unrelated
# `func toggle(_ animated: Bool)` can never demote a real violation to
# `external`. The strict direction is deliberate — a name shared with an
# unrelated zero-argument `func` is still reported — and the only exemption is
# the forwarded closure value described next.
#
# Forwarded closure values: `Button(action: openSettings)` forwards a stored
# closure (`let openSettings: () -> Void` at PopoverFooterView.swift:18, used at
# :32) or a closure parameter (`using read: (AudioObjectPropertyElement) ->
# UInt32?` at VolumeMonitor.swift:366, used at :369). That is a value, not a
# method reference, so when the reference's own file declares the name with a
# function type the reference is `external`. Without that exemption an unrelated
# `func openSettings()` elsewhere would turn the protected forward into a
# violation, and `read` would become a twelfth real-tree finding.
#
# Known limits (non-goals). A bash guard has no type information, so these
# shapes are deliberately not detected rather than guessed at: a guessed
# detection is a false positive, and a guard that cries wolf gets switched off.
#   1. Argument-taking method references, e.g. `.map(probe.handleTransform)`,
#      where the reference feeds a function type that takes arguments.
#   2. Non-argument positions, e.g. `let handler: () -> Void = probe.handleX`.
#   3. Argument labels outside the families above, e.g. `perform:` in
#      `.onTapGesture(perform:)`.
#   4. A value that ends its line without `)` or `,`, which the scan's
#      terminator requirement cannot see.
# The CI preflight (AGENTS.md: `swift test`, `swift build -c release`, and a
# non-publishing release workflow run), not this guard, is the authority for
# compiler-level behaviour.
#
# False-positive policy: the rule errs strict on purpose. Nonisolated methods
# declared in this repo are flagged too, so each one needs an allowlist entry
# with a written justification. That keeps a reviewer in the loop instead of
# silently trusting a heuristic that cannot see isolation.
#
# Usage: check-forbidden-patterns.sh [--root <dir>] [--list] [--self-test]
# Exit codes: 0 = clean, 1 = violations found or a self-test assertion failed,
#             2 = the arguments are unusable.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="scan"

# identifier<TAB>justification
ALLOWED=(
  "isOutputDevice	nonisolated private func, CoreAudioOutputController.swift:155; .filter(isOutputDevice) at :24 runs in a nonisolated method, so no isolation thunk is generated."
  "networkConfiguration	CoreWLANNetworkWorker (WiFiNetworkController.swift:79) is a nonisolated final class; the reference at :257 runs on its serial queue."
  "projectCandidate	CoreWLANNetworkWorker (WiFiNetworkController.swift:79) is a nonisolated final class; the reference at :130 runs on its serial queue."
  "removeObserver	Foundation API, nonisolated; used as observers.forEach(notificationCenter.removeObserver) at SystemIconAppearanceMonitor.swift:53 and MainMenuController.swift:61."
)

usage() {
    echo "Usage: $0 [--root <dir>] [--list] [--self-test]" >&2
}

# One line per `<label>: <value>` pair on the line, `<label>` first and the
# value's first token second. Every argument label counts, not just the six the
# scan looks for: `requestWiFiNameAccess: handleRequestWiFiNameAccess` is the
# same function-value position as `action:`.
labelled_values() {
    grep -oE '[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*' <<<"$1" || true
}

# The identifier this value token refers to, cut back to the last position
# where it is still followed by an argument boundary: a bare capture has to
# cope with `using: read) == 1`, which no anchored `sed` pattern gets right.
value_identifier() {
    local captured="$1" rest head

    while [[ -n "$captured" ]]; do
        head="${captured%%[^A-Za-z0-9_.]*}"
        rest="${captured#"$head"}"
        # A space, a bracket or a brace means the argument ended here. Anything
        # else (an operator such as `== 1`) means this substring is not the
        # argument itself, so cut a character and try again.
        if [[ -z "$rest" || "${rest:0:1}" == " " || "${rest:0:1}" == $'\t' \
            || "$rest" == ")"* || "$rest" == ","* || "$rest" == "}"* \
            || "$rest" == "{"* || "$rest" == "("* || "$rest" == "]"* ]]; then
            echo "$head"
            return 0
        fi
        captured="$head"
    done
}

# Prints one identifier per function-value position on the line. A line may
# hold several, and each one is judged on its own.
shape_identifiers() {
    local line="$1"
    local pair value name found=0

    while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        value="${pair#*:}"
        value="${value#"${value%%[![:space:]]*}"}"
        name="$(value_identifier "$value")"
        [[ -n "$name" ]] || continue
        echo "$name"
        found=1
    done < <(labelled_values "$line")

    # A sequence operator applied to a single token. The argument may itself
    # carry a label (`networkConfiguration(interface:)`), so nothing is required
    # after the closing parenthesis.
    local call
    call="$(sed -nE \
        's/.*\.(map|compactMap|filter|forEach|sink|assign)\([[:space:]]*([A-Za-z_][A-Za-z0-9_.]*)[(,) ].*/\2/p' \
        <<<"$line")"
    if [[ -n "$call" ]]; then
        echo "$call"
        found=1
    fi

    if [[ "$found" == "0" ]] && grep -qE '(^|[^.[:alnum:]_])callAsFunction' <<<"$line"; then
        # A `.callAsFunction` reference is unconditional: Swift synthesizes the
        # method, so there is no `func callAsFunction` declaration to look up.
        name="$(sed -nE 's/.*\.([A-Za-z_][A-Za-z0-9_.]*\.callAsFunction).*/\1/p' <<<"$line")"
        echo "${name:-callAsFunction}"
        found=1
    fi

    # No function-value position at all: the shape was recorded so that the
    # report shows it was considered, but there is nothing to resolve. The
    # scan patterns cannot produce this today (every one of them implies a
    # label, an operator call or a `.callAsFunction`), so it is a fallback.
    if [[ "$found" == "0" ]]; then
        echo "external"
    fi
}

# The token referenced as a function value, exactly as captured. Rule 2 is
# applied by the caller (`is_rule2_shape`) rather than here, because `--list`
# reports the captured token for a dropped shape: `URL.init` says what was
# considered, where the literal `external` said nothing.
extract_identifier() {
    shape_identifiers "$1" | head -1
}

# Rule 2: a keypath, an inline closure, a call, or a library initializer
# reference is a value, not a method reference. The scan patterns require an
# identifier start, so these tokens cannot be captured today and the arms are
# unreachable in practice; they are kept as the literal implementation of rule 2
# so that a later widening of the scan (for example to argument-taking method
# references, or to `<Type>.init` tokens the operator arm already sees) cannot
# silently turn them into violation candidates.
is_rule2_shape() {
    case "$1" in
        ""|\\*|*'('*|*'{'*) return 0 ;;
        *'.init'|init) return 0 ;;
    esac
    return 1
}

# True when `name` is declared under Sources/ as a method that takes no
# arguments. The lookup fails closed on overloads: one zero-argument declaration
# is enough, so `func toggle()` plus `func toggle(_ animated: Bool)` anywhere in
# the tree still reports every reference to `toggle`. Requiring *every*
# declaration to be zero-argument let an unrelated overload silence a real
# violation.
has_zero_arg_declaration() {
    local name="$1" root="$2"
    local decls
    decls="$(grep -rhoE "func ${name}\(\)" "$root/Sources" --include='*.swift' || true)"
    [[ -n "$decls" ]]
}

# True when `name` is a function-typed value declared in the same file as the
# reference — a stored property (`let openSettings: () -> Void`) or a closure
# parameter (`using read: (AudioObjectPropertyElement) -> UInt32?`). The
# identifier in `Button(action: openSettings)` then forwards that value, so an
# unrelated same-named `func` elsewhere must not make it a violation.
is_forwarded_closure() {
    local name="$1" path="$2"
    [[ -f "$path" ]] || return 1
    grep -qE "(^|[^A-Za-z0-9_.])${name}[[:space:]]*:[^=]*->" "$path"
}

is_allowlisted() {
    local name="$1" entry
    for entry in "${ALLOWED[@]}"; do
        if [[ "${entry%%$'\t'*}" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}

# Prints `<path>:<line>:<verdict>:<name>` for every considered shape and returns
# 1 when at least one of them is a violation.
report() {
    local root="$1"
    local -a violations=()
    local line location path lineno text name lookup display verdict found

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        # `grep -rn` emits `<path>:<line>:<text>`. The path itself may contain
        # a colon on macOS (`/var/folders/.../T/tmp.X`), so peel the two fixed
        # trailing fields off instead of splitting on the first colon.
        text="${line#*:}"
        text="${text#*:}"
        location="${line%"$text"}"
        path="${location%:}"
        lineno="${path##*:}"
        path="${path%:*}"

        name="$(extract_identifier "$text")"

        # The identifier that gets looked up: `dismiss.callAsFunction` resolves
        # as `callAsFunction`. A rule-2 shape keeps the captured token instead,
        # which is what --list prints for it.
        lookup="${name##*.}"
        display="$lookup"

        if [[ "$name" == "external" ]] || is_rule2_shape "$name"; then
            verdict="external"
            display="$name"
        elif is_allowlisted "$lookup"; then
            # The allowlist is consulted before the declaration lookup: an
            # allowlisted method may take arguments (`.filter(isOutputDevice)`
            # passes `(AudioDeviceID) -> Bool`), and its entry is exactly the
            # record that a reviewer checked that reference.
            verdict="allowed"
        elif [[ "$lookup" == "callAsFunction" ]]; then
            # Synthesized by the compiler, so `has_zero_arg_declaration` cannot
            # see it.
            verdict="violation"
        elif has_zero_arg_declaration "$lookup" "$root" \
            && ! is_forwarded_closure "$lookup" "$path"; then
            verdict="violation"
        else
            verdict="external"
        fi

        # `--list` shows every considered shape; a plain run stays quiet about
        # the ones that are fine so the violation list is the whole output.
        if [[ "$MODE" == "list" ]]; then
            printf '%s:%s:%s:%s\n' "$path" "$lineno" "$verdict" "$display"
        fi
        if [[ "$verdict" == "violation" ]]; then
            violations+=("$path:$lineno:$display")
        fi
    done < <(scan_shapes "$root" | LC_ALL=C sort)

    if (( ${#violations[@]} == 0 )); then
        return 0
    fi

    # Only a plain scan explains itself on stderr: `--list` keeps stdout
    # machine-readable and stays quiet, and `--self-test` reads the verdicts
    # from the same listing and prints its own failures.
    if [[ "$MODE" == "scan" ]]; then
        {
            echo "Forbidden pattern: an actor-isolated method is passed as a function value."
            echo "AGENTS.md requires an explicit closure instead, e.g."
            echo "  requestWiFiNameAccess: { self.handleRequestWiFiNameAccess() }"
            echo ""
            for found in "${violations[@]}"; do
                echo "  ${found}"
            done
            echo ""
            echo "${#violations[@]} violation(s) found. See docs/swift-ci-compatibility.md."
        } >&2
    fi

    return 1
}

scan_shapes() {
  local root="$1"
  grep -rnE \
    -e '(action|get|set|using|block|request[A-Za-z0-9_]*|open[A-Za-z0-9_]*):[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[),]' \
    -e '\.(map|compactMap|filter|forEach|sink|assign)\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*\)' \
    -e '\.(map|compactMap|filter|forEach|sink|assign)\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*\(' \
    -e '\.callAsFunction\b' \
    "$root/Sources" --include='*.swift' || true
}

self_test() {
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    mkdir -p "$tmp/Sources"

    # 1. A bare method reference on an explicitly actor-isolated type.
    cat >"$tmp/Sources/MainActorMethod.swift" <<'SWIFT'
import SwiftUI

@MainActor
final class Probe {
    func handleThing() {}
}

struct ProbeCaller: View {
    let probe = Probe()

    var body: some View {
        Button(action: handleThing) { EmptyView() }
    }
}
SWIFT

    # 2. The same shape where isolation is only inferred: `View` is @MainActor.
    cat >"$tmp/Sources/ViewMethod.swift" <<'SWIFT'
import SwiftUI

struct ProbeView: View {
    private func toggle() {}

    var body: some View {
        Button(action: toggle) { EmptyView() }
    }
}
SWIFT

    # 3. A `.callAsFunction` reference, which has no `func` declaration.
    cat >"$tmp/Sources/CallAsFunction.swift" <<'SWIFT'
import SwiftUI

struct DismissProbe: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) { EmptyView() }
    }
}
SWIFT

    # 4. A `func` that takes an argument can never fill a bare-identifier
    #    function-value slot, so `title:` is an ordinary labelled argument. If
    #    the arity half of the rule is lost, this line turns red.
    cat >"$tmp/Sources/ArityGuard.swift" <<'SWIFT'
import SwiftUI

struct ArityProbe: View {
    func label(_ localization: String) -> String { localization }

    var body: some View {
        Button(action: label) { EmptyView() }
    }
}
SWIFT

    # 5. An allowlisted declaration must keep its `allowed` verdict rather than
    #    sliding into `violation` or being counted as an unresolved external.
    cat >"$tmp/Sources/Allowlisted.swift" <<'SWIFT'
import Foundation

struct AllowlistedProbe {
    nonisolated private func isOutputDevice(_ deviceID: Int) -> Bool { deviceID != 0 }
    nonisolated private func removeObserver(_ token: NSObjectProtocol) {}

    func use(tokens: [NSObjectProtocol], ids: [Int]) {
        tokens.forEach(removeObserver)
        _ = ids.filter(isOutputDevice)
    }
}
SWIFT

    # 6. Every shape that must stay silent: allowlisted nonisolated methods,
    #    out-of-repo declarations, initializer references, keypaths, and the
    #    closure properties this repo forwards by name, which are values
    #    rather than method references.
    cat >"$tmp/Sources/SafeShapes.swift" <<'SWIFT'
import SwiftUI

struct SafeShapes: View {
    let onShowIconGuide: () -> Void
    let onOpenDetails: () -> Void
    let onOpenBluetoothSettings: () -> Void
    let onRequestNameAccess: () -> Void
    let onOpenLocationSettings: () -> Void
    let onToggleMute: () -> Void
    let onOpenBatterySettings: () -> Void
    let action: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onCustomize: () -> Void
    let onOpenBatteryDetails: () -> Void
    let openSettings: () -> Void

    func use(
        observers: [NSObjectProtocol],
        center: NotificationCenter,
        candidates: [String],
        rawNetworks: [Int],
        interface: String?
    ) {
        observers.forEach(center.removeObserver)
        _ = candidates.compactMap(URL.init(string:))
        _ = candidates.map(\.element)
        _ = rawNetworks.filter(isOutputDevice)
        _ = rawNetworks.compactMap(projectCandidate)
        _ = interface.map(networkConfiguration(interface:))

        Button(action: onShowIconGuide) { EmptyView() }
        Button(action: onOpenDetails) { EmptyView() }
        Button(action: onOpenBluetoothSettings) { EmptyView() }
        Button(action: onRequestNameAccess) { EmptyView() }
        Button(action: onOpenLocationSettings) { EmptyView() }
        Button(action: onToggleMute) { EmptyView() }
        Button(action: onOpenBatterySettings) { EmptyView() }
        Button(action: action) { EmptyView() }
        Button(action: onOpenWiFiSettings) { EmptyView() }
        Button(action: onCustomize) { EmptyView() }
        Button(action: onOpenBatteryDetails) { EmptyView() }
        Button(action: openSettings) { EmptyView() }
        Button(action: quit) { EmptyView() }
    }
}
SWIFT

    # 7. The `request*:` / `open*:` label families, which is how this repo
    #    forwards its action callbacks (StatusBarController.swift:208-215). No
    #    other family in the scan matches `requestWiFiNameAccess:` or
    #    `openBatterySettings:` (`openBatterySettings` ends in `Settings:`, not
    #    `set:`), so deleting the families from `scan_shapes` drops both of
    #    these back to `external` and fails the count and verdict assertions.
    cat >"$tmp/Sources/LabelFamilies.swift" <<'SWIFT'
import SwiftUI

@MainActor
final class LabelFamilyProbe {
    func handleRequestWiFiNameAccess() {}
    func handleOpenBatterySettings() {}
}

struct LabelFamilyCaller: View {
    private let probe = LabelFamilyProbe()

    var body: some View {
        StatusPopoverProbe(
            requestWiFiNameAccess: handleRequestWiFiNameAccess,
            openBatterySettings: handleOpenBatterySettings,
            quit: quitAction
        )
    }
}
SWIFT

    # 8. Fail closed on overloads: the argument-taking overload lives in a
    #    different file, exactly like an unrelated overload added anywhere under
    #    Sources/, and must not demote the zero-argument declaration's
    #    violation.
    cat >"$tmp/Sources/OverloadTarget.swift" <<'SWIFT'
import SwiftUI

@MainActor
final class OverloadProbe {
    func reloadWithOverload() {}
}

struct OverloadCaller: View {
    private let probe = OverloadProbe()

    var body: some View {
        Button(action: reloadWithOverload) { EmptyView() }
    }
}
SWIFT

    cat >"$tmp/Sources/OverloadElsewhere.swift" <<'SWIFT'
import Foundation

extension OverloadProbe {
    func reloadWithOverload(_ animated: Bool) {}
}
SWIFT

    # 9. A forwarded closure is a value: an unrelated same-named zero-argument
    #    `func` must not turn `Button(action: openSettings)` into a violation,
    #    with or without an argument-taking overload beside it. This is the
    #    shape `openSettings` has at PopoverFooterView.swift:32 and
    #    StatusPopoverView.swift:327.
    cat >"$tmp/Sources/ClosureCollision.swift" <<'SWIFT'
import SwiftUI

struct ClosureCollisionProbe: View {
    let openPreferences: () -> Void
    let openSettings: () -> Void

    var body: some View {
        Button(action: openPreferences) { EmptyView() }
        Button(action: openSettings) { EmptyView() }
    }
}

struct ClosureCollisionHelper {
    static func openPreferences() {}
    static func openPreferences(_ animated: Bool) {}
    static func openSettings() {}
}
SWIFT

    # `name:verdict` expectations, one per fixture shape. Kept as two parallel
    # indexed arrays because /bin/bash on macOS is 3.2 and has no `declare -A`.
    local -a expect=()

    expect+=("handleThing:violation")
    expect+=("toggle:violation")
    expect+=("callAsFunction:violation")

    # The `request*`/`open*` label families (fixture 7).
    expect+=("handleRequestWiFiNameAccess:violation")
    expect+=("handleOpenBatterySettings:violation")

    # Fail closed on overloads (fixture 8).
    expect+=("reloadWithOverload:violation")

    # The allowlist, consulted before the arity test.
    expect+=("removeObserver:allowed")
    expect+=("isOutputDevice:allowed")

    # Declared under Sources/ but never in a flaggable position, or resolving to
    # a declaration this repo does not own.
    expect+=("projectCandidate:allowed")
    expect+=("networkConfiguration:allowed")
    expect+=("label:external")
    expect+=("URL.init:external")
    expect+=("onShowIconGuide:external")
    expect+=("onOpenDetails:external")
    expect+=("onOpenBluetoothSettings:external")
    expect+=("onRequestNameAccess:external")
    expect+=("onOpenLocationSettings:external")
    expect+=("onToggleMute:external")
    expect+=("onOpenBatterySettings:external")
    expect+=("action:external")
    expect+=("onOpenWiFiSettings:external")
    expect+=("onCustomize:external")
    expect+=("onOpenBatteryDetails:external")
    expect+=("openSettings:external")
    expect+=("openPreferences:external")
    expect+=("quit:external")

    local reported failed=0
    local expected_violations=6

    # `report` only prints the per-shape verdict lines in `--list` mode, so the
    # self-test drives it that way and reads the verdicts from stdout.
    MODE="list"
    reported="$(report "$tmp" 2>/dev/null)" || true
    MODE="self-test"

    local violations
    violations="$(grep -c ':violation:' <<<"$reported" || true)"
    echo "self-test: ${violations}/${expected_violations} violations detected"
    if [[ "$violations" != "$expected_violations" ]]; then
        echo "  expected ${expected_violations} synthetic methods to be flagged, got ${violations}" >&2
        failed=1
    fi

    local i pair name verdict found
    for (( i = 0; i < ${#expect[@]}; i++ )); do
        pair="${expect[$i]}"
        name="${pair%%:*}"
        verdict="${pair#*:}"
        found="$(sed -nE "s/^.*:[0-9]+:([a-z]+):([A-Za-z0-9_.]*\.)?${name}$/\1/p" \
            <<<"$reported" | head -1)"
        if [[ "$found" != "$verdict" ]]; then
            echo "  expected ${name}:${verdict}, got ${name}:${found:-<not reported>}" >&2
            failed=1
        fi
    done

    # The safe shapes the fixture exists to protect, from the brief, each paired
    # with the fixture text that exercises it. Both halves are asserted: the
    # fixture text must be present, and the shape must never be reported as a
    # violation. For `element` the second half cannot fail on its own — the scan
    # patterns require an identifier start, so `\.element` is dropped before
    # classification and never reaches the report — which is exactly why the
    # fixture-presence half exists: an assertion about a shape no fixture
    # exercises could not fail. `URL.init` does reach the report and is asserted
    # per-shape in the list above, so a broken rule-2 `.init` arm is caught.
    local -a safe_shapes=(
        "removeObserver	forEach(removeObserver)"
        "isOutputDevice	filter(isOutputDevice)"
        "projectCandidate	compactMap(projectCandidate)"
        "networkConfiguration	map(networkConfiguration(interface:))"
        "URL	compactMap(URL.init(string:))"
        "element	map(\\.element)"
        "onOpenBatterySettings	Button(action: onOpenBatterySettings)"
    )

    local safe_count=0 shape evidence
    for (( i = 0; i < ${#safe_shapes[@]}; i++ )); do
        pair="${safe_shapes[$i]}"
        shape="${pair%%$'\t'*}"
        evidence="${pair#*$'\t'}"
        if ! grep -rqF -- "$evidence" "$tmp/Sources"; then
            echo "  no fixture exercises the safe shape ${shape} (missing: ${evidence})" >&2
            failed=1
        fi
        if ! grep -qE ":violation:([A-Za-z0-9_.]*\.)?${shape}$" <<<"$reported"; then
            (( safe_count += 1 ))
        fi
    done
    echo "self-test: ${safe_count}/${#safe_shapes[@]} safe shapes ignored"
    if (( safe_count != ${#safe_shapes[@]} )); then
        echo "  expected all ${#safe_shapes[@]} brief shapes to be ignored" >&2
        failed=1
    fi

    if (( failed != 0 )); then
        {
            echo "self-test fixture scan reported:"
            echo "$reported"
        } >&2
        return 1
    fi
    return 0
}

while (( $# > 0 )); do
    case "$1" in
        --root)
            if (( $# < 2 )); then
                echo "Error: --root requires a directory." >&2
                usage
                exit 2
            fi
            shift
            ROOT="$1"
            ;;
        --list) MODE="list" ;;
        --self-test) MODE="self-test" ;;
        -h|--help)
            usage
            exit 2
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

if [[ ! -d "$ROOT/Sources" ]]; then
    echo "Error: no Sources directory under $ROOT." >&2
    usage
    exit 2
fi

if [[ "$MODE" == "self-test" ]]; then
    self_test
    exit $?
fi

if [[ "$MODE" == "list" ]]; then
    report "$ROOT" || true
    exit 0
fi

if report "$ROOT"; then
    echo "No forbidden actor-isolated method references found under $ROOT/Sources"
    exit 0
fi
exit 1
