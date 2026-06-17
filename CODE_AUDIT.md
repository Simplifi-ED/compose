## 1. Executive summary
1. **[High] Runtime GPU support correctly fails fast** — §5.1 — `Sources/ComposeCore/Runtime/DeployGPUPlanning.swift:3-27`
2. **[Medium] Parser now enforces strict reservation schema** — §5.2 — `Sources/ComposeCore/Model/ComposeDeployResources.swift:132-171`
3. **[Medium] `compose config` preserves reservation output** — §8.1 — `Sources/ComposeCore/Parser/ComposeServiceEncodable.swift:30-43`
4. **[Medium] `config --quiet` validates unsupported runtime path** — §3.1 — `Sources/ComposeCore/Parser/ComposeConfigResolver.swift:68-89`
5. **[Low] Scale override preserves existing deploy resources** — §9.1 — `Sources/ComposeCore/Model/ComposeService.swift:174-198`

## 2. Quick wins
### 2.1 Add machine-specific coverage
- **Location:** `Sources/compose-verify/TestRunner+ResourceLimitsValidation.swift:7-209`
- **What:** Current tests assert host-mode unsupported GPU behavior but do not assert machine-context wording path.
- **Why:** Machine-specific error messages can regress silently.
- **Action:** Add one test path where `machineName` is present in planning context.
- **Severity:** Low

## 3. Concurrency
### 3.1 Quiet-mode validation remains synchronous and deterministic
- **Location:** `Sources/ComposeCore/Parser/ComposeConfigResolver.swift:84-125`
- **What:** GPU reservation validation for `config --quiet` is pure and synchronous.
- **Why:** No new concurrency hazards introduced in changed paths.
- **Action:** No change required.
- **Severity:** Low

## 4. API modernity
*No findings.*

## 5. Bugs / logic errors
### 5.1 Explicit unsupported-runtime guard prevents silent misconfiguration
- **Location:** `Sources/ComposeCore/Runtime/DeployGPUPlanning.swift:3-27`
- **What:** Any parsed GPU reservation now raises `invalidField` with actionable guidance when runtime support is unavailable.
- **Why:** Prevents silent acceptance of unsupported GPU requests.
- **Action:** Keep this fail-fast path until runtime flags become available.
- **Severity:** High

### 5.2 Driver/capability validation enforces in-scope contract
- **Location:** `Sources/ComposeCore/Model/ComposeDeployResources.swift:138-167`
- **What:** Parser rejects non-`apple` drivers and non-`gpu` capabilities.
- **Why:** Prevents unsupported device schemas from entering planner paths.
- **Action:** Keep strict validation; extend only when runtime support expands.
- **Severity:** Medium

## 6. Security
### 6.1 Security posture documented as explicit opt-in
- **Location:** `README.md:419-446`, `README.md:845-869`
- **What:** README states default-off behavior and attack-surface increase for GPU passthrough.
- **Why:** Reduces unsafe assumptions and improves operator awareness.
- **Action:** Keep docs aligned with runtime behavior.
- **Severity:** Medium

## 7. Performance
*No findings.*

## 8. SwiftUI / UI
### 8.1 Config rendering path includes reservation content when present
- **Location:** `Sources/ComposeCore/Parser/ComposeServiceEncodable.swift:30-43`
- **What:** Deploy resources export now gates on `resources.hasContent`, preserving reservation serialization.
- **Why:** Avoids output-loss regressions in `compose config`.
- **Action:** No change required.
- **Severity:** Medium

## 9. Dead code / duplication / refactor
### 9.1 Scale override no longer drops deploy resources
- **Location:** `Sources/ComposeCore/Model/ComposeService.swift:174-198`
- **What:** `withDeploy(replicas:)` now retains existing `resources` while overriding replicas.
- **Why:** Prevents accidental loss of limits/reservations during `--scale` resolution.
- **Action:** No change required.
- **Severity:** Low

## 10. Cross-cutting recommendations
### 10.1 Add future-toggle note for runtime enablement
- **Location:** `Sources/ComposeCore/Runtime/DeployGPUPlanning.swift:3-27`
- **What:** Unsupported guard is correct today but will be touched when runtime GPU flags land.
- **Why:** A clear transition note lowers risk during future enablement.
- **Action:** Add a concise implementation comment pointing to upstream capability gate.
- **Severity:** Low

## 11. What was NOT audited
- Full repository historical code paths outside changed files.
- Metal kernel or graphics workload correctness.
- Runtime behavior on future container versions beyond 1.0.0.
- End-to-end machine-mode execution with real GPU passthrough (unsupported today).

## 12. Verification
- **§5.1** — open `Sources/ComposeCore/Runtime/DeployGPUPlanning.swift`, lines 3-27.
- **§5.2** — open `Sources/ComposeCore/Model/ComposeDeployResources.swift`, lines 138-167.
- No Critical findings in this focused audit scope.
