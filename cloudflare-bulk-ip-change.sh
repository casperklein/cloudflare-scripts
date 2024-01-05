#!/bin/bash

DEBUG=0            # 0 = disabled; 1 = show API request & response
TOKEN="change-me"  # "Edit zone DNS" read/write access for all zones
UPDATE=0           # 0 = dry run; 1 = update records

IP_OLD="1.2.3.4"
IP_NEW="5.6.7.8"

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

echo "Querying all zones for A records with the old IP $IP_OLD"
echo "New IP: $IP_NEW"
echo

# get all zones
# https://developers.cloudflare.com/api/operations/zones-get
makeRequest https://api.cloudflare.com/client/v4/zones

while read -r ZONE ZONE_ID; do
	echo "Zone:   $ZONE" # / $ZONE_ID"

	# https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records
	URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&content=$IP_OLD"
	makeRequest "$URL"

	while read -r RESULT_RECORD_ID RESULT_DOMAIN RESULT_IP; do
		echo "Record: $RESULT_DOMAIN ($RESULT_IP)"
		echo -n "Update: $RESULT_IP --> $IP_NEW"

		if [ "$UPDATE" -eq 1 ]; then
			echo
			# Update DNS record
			# https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-patch-dns-record
			URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RESULT_RECORD_ID"
			read -r -d '#' DATA <<-DATA
				{
					"content": "$IP_NEW",
					"name": "$RESULT_DOMAIN",
					"type": "A"
				}
				#
			DATA
			makeRequest --request PATCH --url "$URL" --data "$DATA"
		else
			echo " (dry run)"
		fi
	done < <(jq -r '.result[] | [ .id, .name, .content ] | @tsv' <<< "$RESULT")
	echo
done < <(jq -r '.result[] | [ .name, .id ] | @tsv' <<< "$RESULT")
