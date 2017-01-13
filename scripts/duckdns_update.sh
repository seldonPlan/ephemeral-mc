#!/bin/sh

DOMAIN_NAME=$1
DUCKDNS_TOKEN=$2
DUCKDNS_URL="https://www.duckdns.org/update"
DUCKDNS_QRY="?domains=$DOMAIN_NAME&token=$DUCKDNS_TOKEN&ip="

CURL_TARGET="$DUCKDNS_URL$DUCKDNS_QRY"

printError() {
    printf "ERROR $1\n"
    exit 1
}

[ -z "$DOMAIN_NAME" ] && printError "Domain name required"
[ -z "$DUCKDNS_TOKEN" ] && printError "DuckDNS Token Required"

RESPONSE=$(curl -k "$CURL_TARGET")

if [ "$RESPONSE" = "OK" ]; then
    printf "INFO DNS update successful\n"
    exit 0
elif [ "$RESPONSE" = "KO" ]; then
    printError "DNS Update failed"
else
    printError "Unknown response from $DUCKDNS_URL$DUCKDNS_QRY: [$RESPONSE]"
fi