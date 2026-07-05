# Release helpers — see docs/release.md.

# Matches both the new bare form (vX.Y.Z) and the legacy -beta suffix, so
# scanning history for "latest" keeps recognizing pre-existing -beta tags even
# though we only ever produce the bare form going forward.
release_tag_regex() {
    printf '^v([0-9]+)\\.([0-9]+)\\.([0-9]+)(-beta)?$'
}


release_tags_desc() {
    local tag="" regex=""
    regex="$(release_tag_regex)"

    while IFS= read -r tag; do
        [[ "${tag}" =~ ${regex} ]] || continue
        printf '%s\n' "${tag}"
    done < <(git tag --list 'v*' --sort=-version:refname)
}


release_latest_tag() {
    local tag=""

    while IFS= read -r tag; do
        [[ -n "${tag}" ]] || continue
        printf '%s\n' "${tag}"
        return 0
    done < <(release_tags_desc)
}


release_head_tag() {
    local tag="" regex=""
    regex="$(release_tag_regex)"

    while IFS= read -r tag; do
        [[ "${tag}" =~ ${regex} ]] || continue
        printf '%s\n' "${tag}"
        return 0
    done < <(git tag --points-at HEAD --list 'v*' --sort=-version:refname)
}


release_head_subject() {
    git log -1 --format=%s HEAD
}


release_commit_type_for_subject() {
    local subject="${1:-}" type="" regex='^([[:alpha:]]+)(\([^)]+\))?(!)?:[[:space:]]*.+$'

    if [[ "${subject}" =~ ${regex} ]]; then
        type="${BASH_REMATCH[1],,}"
        printf '%s\n' "${type}"
        return 0
    fi

    printf 'other\n'
}


release_bump_kind_for_subject() {
    local subject="${1:-}" type=""
    type="$(release_commit_type_for_subject "${subject}")"

    case "${type}" in
        feat)
            printf 'minor\n'
            ;;
        *)
            printf 'patch\n'
            ;;
    esac
}


release_next_tag() {
    local latest_tag="${1:-}" bump_kind="${2:-patch}" major=0 minor=0 patch=0 regex=""
    regex="$(release_tag_regex)"

    if [[ -n "${latest_tag}" ]]; then
        [[ "${latest_tag}" =~ ${regex} ]] || {
            printf "release_next_tag: invalid release tag '%s'\n" "${latest_tag}" >&2
            return 1
        }
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
    fi

    case "${bump_kind}" in
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            printf "release_next_tag: unsupported bump kind '%s'\n" "${bump_kind}" >&2
            return 1
            ;;
    esac

    printf 'v%s.%s.%s\n' "${major}" "${minor}" "${patch}"
}


release_pubspec_baseline() {
    local pubspec_path="${PUBSPEC:-pubspec.yaml}" version_line="" version=""
    if [[ ! -f "${pubspec_path}" ]]; then
        printf "release_pubspec_baseline: pubspec file '%s' not found\n" "${pubspec_path}" >&2
        return 1
    fi
    version_line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "${pubspec_path}" | head -n 1 || true)"
    if [[ -z "${version_line}" ]]; then
        printf "release_pubspec_baseline: no 'version: X.Y.Z+N' line in '%s'\n" "${pubspec_path}" >&2
        return 1
    fi
    version="$(printf '%s\n' "${version_line}" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[[:space:]]*$/\1/')"
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "release_pubspec_baseline: parsed '%s' is not a valid X.Y.Z\n" "${version}" >&2
        return 1
    fi
    printf '%s\n' "${version}"
}


# Compare two X.Y.Z strings. Echoes "1" if a > b, "0" if equal, "-1" if a < b.
# Pure numeric, no pre-release tagging.
_release_version_compare() {
    local a="${1}" b="${2}" a_major=0 a_minor=0 a_patch=0 b_major=0 b_minor=0 b_patch=0
    IFS='.' read -r a_major a_minor a_patch <<< "${a}"
    IFS='.' read -r b_major b_minor b_patch <<< "${b}"
    if (( a_major != b_major )); then
        (( a_major > b_major )) && printf '1\n' || printf -- '-1\n'
        return
    fi
    if (( a_minor != b_minor )); then
        (( a_minor > b_minor )) && printf '1\n' || printf -- '-1\n'
        return
    fi
    if (( a_patch != b_patch )); then
        (( a_patch > b_patch )) && printf '1\n' || printf -- '-1\n'
        return
    fi
    printf '0\n'
}


# Returns the higher of (latest tag's X.Y.Z) and (pubspec's X.Y.Z). If only
# one is present, use that one. If both are missing, error. This makes
# pubspec an explicit input to the tag-bump baseline — pubspec can seed a
# higher version than any tag in the series (e.g. 1.0.0 vs v0.9.9).
release_resolve_baseline() {
    local latest_tag="" latest_version="" pubspec_version="" cmp=""
    latest_tag="$(release_latest_tag || true)"
    pubspec_version="$(release_pubspec_baseline || true)"

    if [[ -z "${latest_tag}" && -z "${pubspec_version}" ]]; then
        printf "release_resolve_baseline: no tags and no pubspec version found\n" >&2
        return 1
    fi

    if [[ -z "${latest_tag}" ]]; then
        printf '%s\n' "${pubspec_version}"
        return 0
    fi
    if [[ -z "${pubspec_version}" ]]; then
        latest_version="${latest_tag#v}"
        printf '%s\n' "${latest_version}"
        return 0
    fi

    latest_version="${latest_tag#v}"
    cmp="$(_release_version_compare "${pubspec_version}" "${latest_version}")"
    case "${cmp}" in
        1)
            printf '%s\n' "${pubspec_version}"
            ;;
        -1|0)
            printf '%s\n' "${latest_version}"
            ;;
        *)
            printf "release_resolve_baseline: unexpected compare result '%s'\n" "${cmp}" >&2
            return 1
            ;;
    esac
}


# Rewrites pubspec.yaml from `version: X.Y.Z+N` to `version: <new_version>+<N+1>`.
# Uses mktemp + mv for an atomic write. Echoes a unified diff so the workflow
# can short-circuit via `git diff --quiet`.
release_bump_pubspec() {
    local new_version="${1:-}" pubspec_path="${PUBSPEC:-pubspec.yaml}" tmp="" line="" current_version="" current_build=0 next_build=0
    if [[ -z "${new_version}" ]]; then
        printf "release_bump_pubspec: new version is required\n" >&2
        return 1
    fi
    if [[ ! "${new_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "release_bump_pubspec: '%s' is not a valid X.Y.Z\n" "${new_version}" >&2
        return 1
    fi
    if [[ ! -f "${pubspec_path}" ]]; then
        printf "release_bump_pubspec: pubspec file '%s' not found\n" "${pubspec_path}" >&2
        return 1
    fi
    line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "${pubspec_path}" | head -n 1 || true)"
    if [[ -z "${line}" ]]; then
        printf "release_bump_pubspec: no 'version: X.Y.Z+N' line in '%s'\n" "${pubspec_path}" >&2
        return 1
    fi
    current_version="$(printf '%s\n' "${line}" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+[[:space:]]*$/\1/')"
    current_build="$(printf '%s\n' "${line}" | sed -E 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)[[:space:]]*$/\1/')"
    next_build=$((current_build + 1))

    tmp="$(mktemp)"
    awk -v repl="version: ${new_version}+${next_build}" '
        /^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$/ {
            print repl
            next
        }
        { print }
    ' "${pubspec_path}" > "${tmp}"
    mv "${tmp}" "${pubspec_path}"

    printf 'pubspec: %s+%d -> %s+%d\n' "${current_version}" "${current_build}" "${new_version}" "${next_build}" >&2
    diff -u <(printf 'version: %s+%s\n' "${current_version}" "${current_build}") \
            <(printf 'version: %s+%s\n' "${new_version}" "${next_build}") || true
}


release_create_tag() {
    local current_tag="" baseline_version="" subject="" bump_kind="" next_tag=""

    current_tag="$(release_head_tag || true)"
    if [[ -n "${current_tag}" ]]; then
        printf '%s\n' "${current_tag}"
        return 0
    fi

    baseline_version="$(release_resolve_baseline || true)"
    if [[ -z "${baseline_version}" ]]; then
        printf "release_create_tag: could not resolve a baseline version\n" >&2
        return 1
    fi
    baseline_version="v${baseline_version}"

    subject="$(release_head_subject)"
    bump_kind="$(release_bump_kind_for_subject "${subject}")"
    next_tag="$(release_next_tag "${baseline_version}" "${bump_kind}")"

    git tag "${next_tag}" HEAD
    printf '%s\n' "${next_tag}"
}


release_changelog_bucket_for_subject() {
    local subject="${1:-}" type=""
    type="$(release_commit_type_for_subject "${subject}")"

    case "${type}" in
        feat) printf 'Features\n' ;;
        fix) printf 'Fixes\n' ;;
        refactor) printf 'Refactors\n' ;;
        perf) printf 'Performance\n' ;;
        docs) printf 'Docs\n' ;;
        *) printf 'Other Changes\n' ;;
    esac
}


release_render_changelog_section() {
    local title="${1:?section title required}" entry=""
    shift || true

    [[ $# -gt 0 ]] || return 0

    printf '### %s\n' "${title}"
    for entry in "$@"; do
        printf -- '- %s\n' "${entry}"
    done
    printf '\n'
}


# Render one day-group of tags.
# Args: previous_tag (may be empty) first_tag last_tag release_date
# Output goes to stdout; caller redirects to the temp file.
_release_flush_group() {
    local previous_tag="${1}" first_tag="${2}" last_tag="${3}" release_date="${4}"
    local log_range="" subject=""
    local -a features=() fixes=() refactors=() performance=() docs=() other_changes=()

    if [[ -n "${previous_tag}" ]]; then
        log_range="${previous_tag}..${first_tag}"
    elif [[ "${first_tag}" != "${last_tag}" ]]; then
        log_range="${last_tag}^..${first_tag}"
    else
        log_range="${first_tag}^!"
    fi

    while IFS= read -r subject; do
        [[ -n "${subject}" ]] || continue
        [[ "${subject}" == *"[skip ci]"* ]] && continue
        case "$(release_changelog_bucket_for_subject "${subject}")" in
            Features)     features+=("${subject}") ;;
            Fixes)        fixes+=("${subject}") ;;
            Refactors)    refactors+=("${subject}") ;;
            Performance)  performance+=("${subject}") ;;
            Docs)         docs+=("${subject}") ;;
            *)            other_changes+=("${subject}") ;;
        esac
    done < <(git log --reverse --format=%s "${log_range}")

    (( ${#features[@]} + ${#fixes[@]} + ${#refactors[@]} + ${#performance[@]} + ${#docs[@]} + ${#other_changes[@]} > 0 )) || return 0

    if [[ "${first_tag}" == "${last_tag}" ]]; then
        printf '## %s (%s)\n\n' "${first_tag}" "${release_date}"
    else
        printf '## %s \xe2\x80\xa6 %s (%s)\n\n' "${first_tag}" "${last_tag}" "${release_date}"
    fi

    release_render_changelog_section "Features" "${features[@]}"
    release_render_changelog_section "Fixes" "${fixes[@]}"
    release_render_changelog_section "Refactors" "${refactors[@]}"
    release_render_changelog_section "Performance" "${performance[@]}"
    release_render_changelog_section "Docs" "${docs[@]}"
    release_render_changelog_section "Other Changes" "${other_changes[@]}"
}


release_generate_changelog() {
    local output_path="${1:-CHANGELOG.md}" tmp_output="" write_stdout=0
    local -a tags=()

    if [[ "${output_path}" == "-" ]]; then
        write_stdout=1
        tmp_output="$(mktemp)"
    else
        mkdir -p "$(dirname -- "${output_path}")"
        tmp_output="${output_path}.tmp"
    fi

    mapfile -t tags < <(release_tags_desc)

    {
        printf '# Changelog\n\n'
        printf '_Generated from release tags with `bash bin/generate-changelog`._\n\n'

        if (( ${#tags[@]} == 0 )); then
            printf 'No release tags yet.\n'
        else
            local -a current_group=()
            local current_group_date="" tag="" tag_date=""

            for index in "${!tags[@]}"; do
                tag="${tags[${index}]}"
                tag_date="$(git log -1 --format=%cs "${tag}^{commit}")"

                if [[ "${tag_date}" == "${current_group_date}" ]]; then
                    current_group+=("${tag}")
                else
                    if (( ${#current_group[@]} > 0 )); then
                        _release_flush_group "${tag}" "${current_group[0]}" "${current_group[-1]}" "${current_group_date}"
                    fi
                    current_group=("${tag}")
                    current_group_date="${tag_date}"
                fi
            done

            if (( ${#current_group[@]} > 0 )); then
                _release_flush_group "" "${current_group[0]}" "${current_group[-1]}" "${current_group_date}"
            fi
        fi
    } > "${tmp_output}"

    if (( write_stdout == 1 )); then
        cat "${tmp_output}"
        rm -f "${tmp_output}"
        return 0
    fi

    mv "${tmp_output}" "${output_path}"
}