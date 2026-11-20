#!/usr/bin/env bash
# Publish a verified bundle. An interrupted draft can be resumed on a rerun.
set -euo pipefail

# shellcheck source=/dev/null
source .github/plugin.env
asset="$PLUGIN_NAME.wasm"
cd release-assets
sha256sum -- "$asset" | cmp - SHA256SUMS
notes="$RUNNER_TEMP/release-notes.md"
channel=()
tag=${RELEASE_TAG:?missing tag from build}

# Check the remote attachment names before publishing a draft or accepting a rerun.
check_assets() {
    local assets
    assets=$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json assets)
    if ! jq -e --arg file "$asset" '([.assets[].name] | sort) == ([$file, "SHA256SUMS"] | sort)' <<< "$assets" >/dev/null; then
        printf 'Unexpected attachments for %s: %s\n' "$tag" "$(jq -c '[.assets[].name]' <<< "$assets")" >&2
        return 1
    fi
}

case "$BUILD_CHANNEL" in
    release)
        [[ "$tag" == "v$PLUGIN_VERSION" ]]
        title="$PLUGIN_NAME $tag"
        prerelease=false
        ;;
    nightly)
        [[ "$tag" == nightly-* ]]
        title="$PLUGIN_NAME $PLUGIN_VERSION"
        prerelease=true
        channel+=(--prerelease --latest=false)
        ;;
    *) echo "Unknown publication channel: $BUILD_CHANNEL" >&2; exit 1 ;;
esac
repo_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
{
    printf 'Build target wasm32-wasip3 (WASI 0.3), using the Pumpkin Wasm 0.2 plugin API.\n\n'
    printf 'Built from [%s](%s/commit/%s).\n' "$GITHUB_SHA" "$repo_url" "$GITHUB_SHA"
} > "$notes"

# A draft can exist before GitHub creates its tag. Verify its target before any write.
if release=$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft,isPrerelease,targetCommitish 2>"$RUNNER_TEMP/release-view.err"); then
    draft=$(jq -r .isDraft <<< "$release")
    [[ "$(jq -r .isPrerelease <<< "$release")" == "$prerelease" ]]
    if [[ "$draft" == true && "$(jq -r .targetCommitish <<< "$release")" != "$GITHUB_SHA" ]]; then
        echo "Draft $tag targets a different commit." >&2
        exit 1
    fi
elif [[ "$(cat "$RUNNER_TEMP/release-view.err")" == 'release not found' ]]; then
    draft=absent
else
    cat "$RUNNER_TEMP/release-view.err" >&2
    exit 1
fi

# Create the exact tag once. Existing lightweight or annotated tags must point at this build.
repo_api="repos/$GITHUB_REPOSITORY"
refs=$(gh api "$repo_api/git/matching-refs/tags/$tag" --jq '.[].ref')
if grep -Fxq "refs/tags/$tag" <<< "$refs"; then
    commit=$(gh api "$repo_api/commits/refs%2Ftags%2F$tag" --jq .sha)
    if [[ "$commit" != "$GITHUB_SHA" ]]; then
        echo "Tag $tag already points at $commit (this build is $GITHUB_SHA)." >&2
        exit 1
    fi
elif [[ "$draft" == false ]]; then
    echo "Published release $tag has no matching tag." >&2
    exit 1
else
    gh api --method POST "$repo_api/git/refs" -f ref="refs/tags/$tag" -f sha="$GITHUB_SHA" --silent
fi

if [[ "$draft" == false ]]; then
    check_assets
    previous=$(mktemp -d)
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir "$previous"
    cmp SHA256SUMS "$previous/SHA256SUMS"
    (cd "$previous" && sha256sum -c SHA256SUMS)
    exit 0
fi
if [[ "$draft" == absent ]]; then
    gh release create "$tag" --repo "$GITHUB_REPOSITORY" --draft --target "$GITHUB_SHA" --verify-tag \
        --title "$title" --notes-file "$notes" "${channel[@]}"
fi

gh release upload "$tag" --repo "$GITHUB_REPOSITORY" --clobber "$asset" SHA256SUMS
check_assets
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false "${channel[@]}"
