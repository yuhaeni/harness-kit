#!/bin/sh
# Stateful, dependency-free workflow manager for a generated project.

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PHASES_DIR="$PROJECT_ROOT/phases"
TEMPLATES_DIR="$PROJECT_ROOT/.harness/templates"

die() {
    printf '%s\n' "error: $*" >&2
    exit 2
}

usage() {
    cat <<'USAGE'
Usage:
  harness phase create PHASE_ID "Title" --approved
  harness step create PHASE_ID STEP_ID "Title" [--depends-on 001,002]
  harness next [PHASE_ID]
  harness step start PHASE_ID STEP_ID
  harness step review PHASE_ID STEP_ID
  harness step complete PHASE_ID STEP_ID
  harness step replan PHASE_ID STEP_ID

State flow:
  planned -> in-progress -> review_required -> completed
  review_required -> planned  (when review changes are requested)
USAGE
}

validate_identifier() {
    case "$1" in
        ""|*[!A-Za-z0-9-]*) die "$2 must contain only letters, numbers, and hyphens: $1" ;;
    esac
}

sed_escape() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

render_template() {
    source_file=$1
    destination_file=$2
    sed \
        -e "s|{{PHASE_ID}}|$(sed_escape "$PHASE_ID")|g" \
        -e "s|{{PHASE_TITLE}}|$(sed_escape "$PHASE_TITLE")|g" \
        -e "s|{{STEP_ID}}|$(sed_escape "${STEP_ID:-}")|g" \
        -e "s|{{STEP_TITLE}}|$(sed_escape "${STEP_TITLE:-}")|g" \
        -e "s|{{STEP_DEPENDS_ON}}|$(sed_escape "${STEP_DEPENDS_ON:-[]}")|g" \
        "$source_file" > "$destination_file"
}

frontmatter_value() {
    field_name=$2
    awk -v field="$field_name" '
        $0 == "---" { separators += 1; next }
        separators == 1 && index($0, field ":") == 1 {
            value = $0
            sub("^" field ":[[:space:]]*", "", value)
            print value
            exit
        }
    ' "$1"
}

phase_file() {
    printf '%s/phases/%s/phase.md' "$PROJECT_ROOT" "$1"
}

step_file() {
    printf '%s/phases/%s/step-%s.md' "$PROJECT_ROOT" "$1" "$2"
}

evidence_file() {
    printf '%s/phases/%s/step-%s-evidence.md' "$PROJECT_ROOT" "$1" "$2"
}

require_phase_approved() {
    phase_document=$(phase_file "$1")
    [ -f "$phase_document" ] || die "phase does not exist: $1"
    phase_state=$(frontmatter_value "$phase_document" status)
    [ "$phase_state" = approved ] || die "phase '$1' is not approved (current: ${phase_state:-missing})"
}

require_step() {
    requested_step_file=$(step_file "$1" "$2")
    [ -f "$requested_step_file" ] || die "step does not exist: $1/$2"
}

update_step_state() {
    phase_id=$1
    step_id=$2
    expected_state=$3
    new_state=$4
    document=$(step_file "$phase_id" "$step_id")
    current_state=$(frontmatter_value "$document" status)
    [ "$current_state" = "$expected_state" ] || die "cannot change $phase_id/$step_id from '${current_state:-missing}' to '$new_state'; expected '$expected_state'"

    temporary_document=$(mktemp "${TMPDIR:-/tmp}/harness-step.XXXXXX")
    trap 'rm -f "$temporary_document"' EXIT HUP INT TERM
    awk -v replacement="$new_state" '
        $0 == "---" { separators += 1 }
        separators == 1 && /^status:[[:space:]]*/ { print "status: " replacement; changed = 1; next }
        { print }
        END { if (!changed) exit 3 }
    ' "$document" > "$temporary_document" || die "failed to update state in $document"
    mv "$temporary_document" "$document"
    trap - 0
    trap - HUP INT TERM

    evidence=$(evidence_file "$phase_id" "$step_id")
    if [ -f "$evidence" ]; then
        printf '%s\n' "- $(date '+%Y-%m-%d %H:%M:%S %z'): \`$current_state\` → \`$new_state\`" >> "$evidence"
    fi
    printf '%s\n' "$phase_id/$step_id: $current_state -> $new_state"
}

dependencies_completed() {
    phase_id=$1
    step_id=$2
    explain=${3:-false}
    document=$(step_file "$phase_id" "$step_id")
    dependencies=$(frontmatter_value "$document" depends_on)
    case "$dependencies" in
        ""|"[]") return 0 ;;
    esac

    if ! printf '%s\n' "$dependencies" | tr ',' '\n' | while IFS= read -r dependency; do
        dependency=$(printf '%s' "$dependency" | tr -d '[:space:]')
        dependency_document=$(step_file "$phase_id" "$dependency")
        if [ ! -f "$dependency_document" ]; then
            [ "$explain" = true ] && printf '%s\n' "$phase_id/$step_id waits for missing dependency: $dependency" >&2
            exit 1
        fi
        dependency_state=$(frontmatter_value "$dependency_document" status)
        if [ "$dependency_state" != completed ]; then
            [ "$explain" = true ] && printf '%s\n' "$phase_id/$step_id waits for $dependency ($dependency_state)" >&2
            exit 1
        fi
    done; then
        return 1
    fi
    return 0
}

create_phase() {
    [ "$#" -eq 3 ] || die "usage: harness phase create PHASE_ID \"Title\" --approved"
    phase_id=$1
    phase_title=$2
    approval_flag=$3
    validate_identifier "$phase_id" "phase id"
    [ "$approval_flag" = --approved ] || die "Phase design must be explicitly approved; pass --approved"
    [ -n "$phase_title" ] || die "phase title cannot be empty"

    PHASE_ID=$phase_id
    PHASE_TITLE=$phase_title
    phase_directory="$PHASES_DIR/$PHASE_ID"
    [ ! -e "$phase_directory" ] || die "phase already exists: $PHASE_ID"
    [ -f "$TEMPLATES_DIR/phase.md.tmpl" ] || die "missing phase template; regenerate the harness"
    mkdir -p "$phase_directory"
    render_template "$TEMPLATES_DIR/phase.md.tmpl" "$phase_directory/phase.md"
    printf '%s\n' "Created approved phase: $PHASE_ID"
}

create_step() {
    [ "$#" -ge 3 ] || die "usage: harness step create PHASE_ID STEP_ID \"Title\" [--depends-on 001,002]"
    phase_id=$1
    step_id=$2
    step_title=$3
    shift 3
    dependencies="[]"
    if [ "$#" -gt 0 ]; then
        [ "$#" -eq 2 ] && [ "$1" = --depends-on ] || die "expected --depends-on step-001,step-002"
        dependencies=$2
    fi

    validate_identifier "$phase_id" "phase id"
    validate_identifier "$step_id" "step id"
    case "$step_id" in step-*) die "pass the id without the 'step-' filename prefix: $step_id" ;; esac
    [ -n "$step_title" ] || die "step title cannot be empty"
    require_phase_approved "$phase_id"
    [ ! -e "$(step_file "$phase_id" "$step_id")" ] || die "step already exists: $phase_id/$step_id"
    [ ! -e "$(evidence_file "$phase_id" "$step_id")" ] || die "evidence file already exists: $phase_id/$step_id"

    PHASE_ID=$phase_id
    PHASE_TITLE=$(frontmatter_value "$(phase_file "$phase_id")" title)
    STEP_ID=$step_id
    STEP_TITLE=$step_title
    STEP_DEPENDS_ON=$dependencies
    if [ "$dependencies" != "[]" ]; then
        if ! printf '%s\n' "$dependencies" | tr ',' '\n' | while IFS= read -r dependency; do
            dependency=$(printf '%s' "$dependency" | tr -d '[:space:]')
            validate_identifier "$dependency" "dependency id"
            case "$dependency" in step-*) exit 1 ;; esac
        done; then
            die "dependencies must be comma-separated Step ids without the 'step-' prefix"
        fi
    fi
    phase_directory="$PHASES_DIR/$PHASE_ID"
    render_template "$TEMPLATES_DIR/step.md.tmpl" "$(step_file "$phase_id" "$step_id")"
    render_template "$TEMPLATES_DIR/step-evidence.md.tmpl" "$(evidence_file "$phase_id" "$step_id")"
    printf '%s\n' "Created planned step: $phase_id/$step_id"
}

list_next() {
    [ "$#" -le 1 ] || die "usage: harness next [PHASE_ID]"
    phase_scope=${1:-}
    found=false
    if [ -n "$phase_scope" ]; then
        validate_identifier "$phase_scope" "phase id"
        phase_directories="$PHASES_DIR/$phase_scope"
        [ -d "$phase_directories" ] || die "phase does not exist: $phase_scope"
    else
        [ -d "$PHASES_DIR" ] || { printf '%s\n' "No eligible planned Steps."; return; }
        phase_directories=$(find "$PHASES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    for phase_directory in $phase_directories; do
        phase_id=$(basename "$phase_directory")
        phase_document="$phase_directory/phase.md"
        [ -f "$phase_document" ] || continue
        [ "$(frontmatter_value "$phase_document" status)" = approved ] || continue
        for document in "$phase_directory"/step-*.md; do
            [ -f "$document" ] || continue
            case "$document" in *-evidence.md) continue ;; esac
            step_id=$(frontmatter_value "$document" id)
            [ "$(frontmatter_value "$document" status)" = planned ] || continue
            if dependencies_completed "$phase_id" "$step_id" false; then
                step_title=$(frontmatter_value "$document" title)
                printf '%s\n' "$phase_id/$step_id — $step_title"
                found=true
            fi
        done
    done
    [ "$found" = true ] || printf '%s\n' "No eligible planned Steps."
}

case "${1:-}" in
    phase)
        [ "${2:-}" = create ] || { usage; exit 2; }
        shift 2
        create_phase "$@"
        ;;
    step)
        action=${2:-}
        case "$action" in
            create) shift 2; create_step "$@" ;;
            start) [ "$#" -eq 4 ] || { usage; exit 2; }; require_step "$3" "$4"; update_step_state "$3" "$4" planned in-progress ;;
            review) [ "$#" -eq 4 ] || { usage; exit 2; }; require_step "$3" "$4"; update_step_state "$3" "$4" in-progress review_required ;;
            complete) [ "$#" -eq 4 ] || { usage; exit 2; }; require_step "$3" "$4"; update_step_state "$3" "$4" review_required completed ;;
            replan) [ "$#" -eq 4 ] || { usage; exit 2; }; require_step "$3" "$4"; update_step_state "$3" "$4" review_required planned ;;
            *) usage; exit 2 ;;
        esac
        ;;
    next)
        shift
        list_next "$@"
        ;;
    --help|-h|"") usage ;;
    *) die "unknown command: $1" ;;
esac
