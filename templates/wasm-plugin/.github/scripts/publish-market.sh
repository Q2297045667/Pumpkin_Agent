#!/usr/bin/env bash
# Upload a checked GitHub release or submit its existing Studio listing for review.
set -euo pipefail

# shellcheck source=/dev/null
source .github/plugin.env
asset="$PLUGIN_NAME.wasm"
listing_name=${MARKET_PLUGIN_NAME:-$PLUGIN_NAME}

# Report a publishing error and stop before making further requests.
fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ ${MARKET_PLUGIN_ID:-} =~ ^[1-9][0-9]*$ ]] || fail 'Set PUMPKIN_MARKET_PLUGIN_ID to the numeric ID from the Studio management URL.'
: "${MARKET_TOKEN:?Set the Pumpkin_Market_Token repository secret.}"
: "${PLUGIN_VERSION:?Missing version from the GitHub release.}"
api=https://market.pumpkinmc.org/api
plugin_url="$api/plugins/$MARKET_PLUGIN_ID"
response=$(mktemp)
trap 'rm -f "$response"' EXIT

# Keep the response body and HTTP status so a hidden draft can use the Studio lookup.
request() {
    local method=$1 url=$2
    shift 2
    http_status=$(curl --silent --show-error --max-time 120 --request "$method" \
        --header "Authorization: Bearer $MARKET_TOKEN" --output "$response" \
        --write-out '%{http_code}' "$@" "$url")
}

# Accept a successful Studio response and show the API error on a failed operation.
require_success() {
    if [[ $http_status != 2?? ]]; then
        fail "Pumpkin Market $1 returned HTTP $http_status $(jq -c '.error // .message // empty' "$response" 2>/dev/null || true)"
    fi
}

# Read the listing state. Studio can hide draft details even from a scoped API key.
read_listing() {
    request GET "$plugin_url"
    if [[ $http_status == 403 || $http_status == 404 ]]; then
        request GET "$api/user/analytics?timeframe=Lifetime&plugin_id=$MARKET_PLUGIN_ID"
        require_success 'listing lookup (hidden drafts require analytics:read)'
        listing=$(jq -ce --arg id "$MARKET_PLUGIN_ID" \
            'first(.timeSeries[] | select(((.plugin_id // .id) | tostring) == $id)) | .id = (.plugin_id // .id)' \
            "$response") || fail 'The configured listing was not found in the developer dashboard.'
    else
        require_success 'listing lookup'
        listing=$(cat "$response")
    fi
    jq -e --arg id "$MARKET_PLUGIN_ID" --arg name "$listing_name" '(.id | tostring) == $id and .name == $name' \
        <<< "$listing" >/dev/null || fail "The configured Market listing does not identify $listing_name."
    status=$(jq -er '.status' <<< "$listing")
    case $status in
        draft|rejected|under_review|published) ;;
        *) fail "Unknown Pumpkin Market listing status: $status" ;;
    esac
}

case ${1:-} in
    upload)
        [[ $RELEASE_TAG == "v$PLUGIN_VERSION" ]] || fail 'Expected a stable GitHub release tag.'
        cd release-assets
        checksum=$(sha256sum -- "$asset")
        printf '%s\n' "$checksum" | cmp - SHA256SUMS || fail "The GitHub release checksum does not match $asset."
        notes=$(printf '%s/releases/tag/%s\nSHA-256: %s' "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" "$RELEASE_TAG" "${checksum%% *}")
        read_listing
        versions=$(jq -c --arg v "$PLUGIN_VERSION" '[.versions[]? | select(.version == $v)]' <<< "$listing")
        current=$(jq -r '.version // empty' <<< "$listing")
        if [[ $versions != '[]' || $current == "$PLUGIN_VERSION" ]]; then
            jq -e --arg notes "$notes" 'length == 1 and .[0].track == "stable" and .[0].release_notes == $notes' \
                <<< "$versions" >/dev/null || fail 'This version already exists. Its release source could not be confirmed.'
            [[ $status == published || $current == "$PLUGIN_VERSION" ]] || fail 'The listing now has a different version awaiting publication.'
            echo 'The same stable GitHub release has already been uploaded.'
        else
            metadata=$(jq -cn --arg version "$PLUGIN_VERSION" --arg notes "$notes" \
                '{version: $version, track: "stable", releaseNotes: $notes}')
            # Studio accepts version updates on the same listing while staff review it.
            request PUT "$plugin_url" --form "wasm=@$asset;type=application/wasm" --form-string "metadata=$metadata"
            require_success 'stable version upload'
            # Read the new version and review state before deciding whether to submit.
            for delay in 0 2 5; do
                sleep "$delay"
                read_listing
                current=$(jq -r '.version // empty' <<< "$listing")
                if [[ $current == "$PLUGIN_VERSION" ]]; then break; fi
            done
            [[ $current == "$PLUGIN_VERSION" ]] || fail "Market accepted the upload but reports version '$current' instead of $PLUGIN_VERSION."
        fi
        echo "Pumpkin Market listing $MARKET_PLUGIN_ID: $PLUGIN_VERSION (status: $status)."
        case $status in
            draft|rejected) needs_review=true ;;
            *) needs_review=false ;;
        esac
        printf 'needs_review=%s\nplugin_id=%s\n' "$needs_review" "$MARKET_PLUGIN_ID" >> "$GITHUB_OUTPUT"
        ;;
    review)
        read_listing
        request GET "$plugin_url/readiness"
        require_success 'readiness check'
        jq -e --arg v "$PLUGIN_VERSION" '.binaryReady == true and .binaryVersion == $v' \
            "$response" >/dev/null || fail 'The current Market binary does not match the version from the upload job.'
        if [[ $status == under_review || $status == published ]]; then
            echo "Market already reports this version as $status."
            exit 0
        fi
        jq -e '.canPublish == true' "$response" >/dev/null || \
            fail "Complete the listing in Studio, then re-run the failed review job: $(jq -c '.missingRequirements' "$response")"
        request POST "$plugin_url/publish"
        require_success 'review submission'
        echo "$listing_name was submitted for Market review."
        ;;
    *) fail 'Expected upload or review.' ;;
esac
