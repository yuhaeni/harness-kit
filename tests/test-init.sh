#!/bin/sh

set -eu

KIT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/harness-kit-test.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

spring_target="$TEMP_DIR/escape-log"
sh "$KIT_DIR/init.sh" init "$spring_target" --profile spring-backend --description "방탈출 기록 서비스" --claude-compat

test -f "$spring_target/AGENTS.md"
test -f "$spring_target/CLAUDE.md"
test -f "$spring_target/.harness/IMPLEMENTATION.md"
test -f "$spring_target/docs/ARCHITECTURE.md"
test -f "$spring_target/docs/ADR/0000-template.md"
test -f "$spring_target/docs/LLM_WIKI.md"
test -f "$spring_target/phases/README.md"
test -f "$spring_target/scripts/harness.sh"
grep -F 'language = "Kotlin"' "$spring_target/harness.toml" >/dev/null
grep -F "방탈출 기록 서비스" "$spring_target/docs/INTENT.md" >/dev/null
sh "$spring_target/scripts/verify-harness.sh" "$spring_target"

workflow="$spring_target/scripts/harness.sh"
if sh "$workflow" phase create unapproved "승인 없는 설계" >/dev/null 2>&1; then
    printf '%s\n' "phase creation without explicit approval was incorrectly allowed" >&2
    exit 1
fi
sh "$workflow" phase create authentication "로그인과 인증" --approved
grep -F 'status: approved' "$spring_target/phases/authentication/phase.md" >/dev/null
sh "$workflow" step create authentication 001 "도메인 모델 추가"
sh "$workflow" step create authentication 002 "로그인 API 추가" --depends-on 001
grep -F 'status: planned' "$spring_target/phases/authentication/step-001.md" >/dev/null
test -f "$spring_target/phases/authentication/step-001-evidence.md"
next_before=$(sh "$workflow" next)
printf '%s\n' "$next_before" | grep -F 'authentication/001' >/dev/null
if printf '%s\n' "$next_before" | grep -F 'authentication/002' >/dev/null; then
    printf '%s\n' "blocked step was incorrectly selected by harness next" >&2
    exit 1
fi
if sh "$workflow" step complete authentication 001 >/dev/null 2>&1; then
    printf '%s\n' "invalid planned-to-completed transition was incorrectly allowed" >&2
    exit 1
fi
sh "$workflow" step start authentication 001
sh "$workflow" step review authentication 001
sh "$workflow" step replan authentication 001
grep -F 'status: planned' "$spring_target/phases/authentication/step-001.md" >/dev/null
sh "$workflow" step start authentication 001
sh "$workflow" step review authentication 001
sh "$workflow" step complete authentication 001
grep -F 'status: completed' "$spring_target/phases/authentication/step-001.md" >/dev/null
next_after=$(sh "$workflow" next)
printf '%s\n' "$next_after" | grep -F 'authentication/002' >/dev/null

dry_target="$TEMP_DIR/dry-run"
sh "$KIT_DIR/init.sh" init "$dry_target" --profile generic --dry-run
test ! -e "$dry_target"

override_target="$TEMP_DIR/override"
sh "$KIT_DIR/init.sh" init "$override_target" --profile spring-backend --set stack.language=Java --no-adr
grep -F 'language = "Java"' "$override_target/harness.toml" >/dev/null
test ! -e "$override_target/docs/ADR/0000-template.md"

existing_target="$TEMP_DIR/existing"
mkdir "$existing_target"
printf '%s\n' keep > "$existing_target/keep.txt"
if sh "$KIT_DIR/init.sh" init "$existing_target" --profile generic >/dev/null 2>&1; then
    printf '%s\n' "expected non-empty target to be rejected" >&2
    exit 1
fi
test "$(cat "$existing_target/keep.txt")" = keep

printf '%s\n' "All harness-kit shell tests passed."
