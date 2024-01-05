#!/bin/bash

BACKUP_DIR="/my/dns-backup/"  # Store backup in this directory
DEBUG=0                       # 0 = disabled; 1 = show API request & response
TOKEN="change-me"             # DNS read access for all zones
FILE_PREFIX="$(date +%F)_"    # Set current date as file prefix

set -ueo pipefail
shopt -s inherit_errexit

checkBinarys() {
        local i
        for i in "$@"; do
                hash "$i" 2>/dev/null || {
                        echo "Binary missing: $i"
                        echo
                        exit 1
                } >&2
        done
}
checkBinarys "curl" "jq"

CURL_OPTIONS=(
	--silent
	--header "Authorization: Bearer $TOKEN"
	--header "Content-Type:application/json"
)

makeRequest() {
	RESULT=$(curl "${CURL_OPTIONS[@]}" "$@")
	SUCCESS=$(jq -r .success <<< "$RESULT")
	if [ "$SUCCESS" != "true" ]; then
		echo "Error: Request failed."
		echo
		jq <<< "$RESULT"
		echo
		exit 1
	fi >&2
	if [ "$DEBUG" -eq 1 ]; then
		printf -- '%s ' curl "$@"
		echo
		echo
		echo "Result:"
		jq <<< "$RESULT"
		echo
		echo ------------------------------
	fi
}

echo "Backup directory: $BACKUP_DIR"
echo

# get all zones
# https://developers.cloudflare.com/api/operations/zones-get
makeRequest https://api.cloudflare.com/client/v4/zones

while read -r ZONE ZONE_ID; do
	if [[ $ZONE == *'/'* ]]; then
		echo "Error: Zone '$ZONE' contains a slash. WTF?"
		echo
		exit
	fi >&2

	echo "Export: $ZONE / $ZONE_ID"
	FILE="$BACKUP_DIR/$FILE_PREFIX$ZONE"
	# https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-export-dns-records
	URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/export"
	if ! curl --fail "${CURL_OPTIONS[@]}" --url "$URL" > "$FILE"; then
		echo "Error: Zone ($ZONE) export failed."
		echo
		exit 1
	fi >&2
	echo
done < <(jq -r '.result[] | [ .name, .id ] | @tsv' <<< "$RESULT")
