#!/bin/bash

DEBUG=0                   # 0 = disabled; 1 = show API request & response
DOMAIN="foo.example.com"  # record to update
PROXIED="false"           # 0 = disable cloudflare proxy; 1 = enable cloudflare proxy
TOKEN="change-me"         # "Edit zone DNS" read/write access for $DOMAIN
ZONE_ID="change-me"       # get zone ID from cloudflare domain overview page

set -ueo pipefail
shopt -s inherit_errexit

APP=${0##*/}

if [ $# -ne 1 ]; then
	echo "Usage: $APP <IP address>"
	echo
	exit 1
fi
IP="$1"

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
checkBinarys "curl" "jq" #"column"

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

# https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records
URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DOMAIN"
makeRequest "$URL"

RESULT_COUNT=$(     jq -r .result_info.count <<< "$RESULT")
RESULT_DOMAIN=$(    jq -r .result[].name     <<< "$RESULT")
RESULT_IP=$(        jq -r .result[].content  <<< "$RESULT")
RESULT_RECORD_ID=$( jq -r .result[].id       <<< "$RESULT")
RESULT_TYPE=$(      jq -r .result[].type     <<< "$RESULT")

# Check if DNS A record exist.
if ! [[ $RESULT_COUNT -eq 1 && $RESULT_DOMAIN == "$DOMAIN" && $RESULT_TYPE == "A" ]]; then
	echo "Error: DNS A record for '$DOMAIN' not found."
	echo
	jq <<< "$RESULT"
	echo
	exit 1
fi

# Update needed?
if [ "$RESULT_IP" == "$IP" ]; then
	echo "Info: $DOMAIN is already resolving to $IP. Aborting.."
	echo
	exit
fi

# Update DNS record
# https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-patch-dns-record
URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RESULT_RECORD_ID"
read -r -d '#' DATA <<-DATA
	{
		"content": "$IP",
		"name": "$DOMAIN",
		"proxied": $PROXIED,
		"type": "A",
		"comment": "Set by $APP script at $(date '+%F %T')",
		"ttl": 1
	}
	#
DATA
makeRequest --request PATCH --url "$URL" --data "$DATA"

# request was successful; do further checks just for safty

RESULT_DOMAIN=$(  jq -r .result.name    <<< "$RESULT")
RESULT_IP=$(      jq -r .result.content <<< "$RESULT")
RESULT_PROXIED=$( jq -r .result.proxied <<< "$RESULT")
RESULT_TYPE=$(    jq -r .result.type    <<< "$RESULT")

if ! [[ $DOMAIN == "$RESULT_DOMAIN" && $IP == "$RESULT_IP" && $PROXIED == "$RESULT_PROXIED" && $RESULT_TYPE == "A" ]]; then
	echo "Error: Something went wrong!"
	echo
	{
	echo ".        Expected  Result"
	echo "Domain:  $DOMAIN   $RESULT_DOMAIN"
	echo "IP:      $IP       $RESULT_IP"
	echo "Type:    A         $RESULT_TYPE"
	echo "Proxied: $PROXIED  $RESULT_PROXIED"
	} | column -t
	echo
	exit 1
fi >&2

echo "Update successful: $DOMAIN => $IP"
echo
