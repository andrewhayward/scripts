#!/bin/bash

function __url_encode {
    echo -n "$@" | perl -pe 's/\s+$//' | perl -pe 's/([^a-zA-Z0-9\-\.\_])/sprintf("%%%02X", ord($1))/seg'
}

function __nonce {
	openssl rand -base64 16 | perl -pe 's/[^\w]//g'
}

function __sign {
	local data=$1 key=$2
	echo -n "${data}" | openssl dgst -sha1 -binary -hmac "${key}" | openssl enc -base64
}

function __signature_base {
	local method=$1 base_uri=$2
	shift
	shift
	local paramString=$(echo -n $(__url_encode "${@}") | perl -pe 's/%20/\n/g' | sort -u | perl -pe 's/\s/%26/g')
	echo -n $(__url_encode "${method}")"&"$(__url_encode "${base_uri}")"&${paramString}" | perl -pe 's/%26$//'
}

function __do_request {
	local baseUri=$1
	shift

	local sigKey=$(__url_encode $TWITTER_CONSUMER_SECRET)"&"$(__url_encode $TWITTER_AUTH_SECRET)
	local timestamp=$(date +%s)
	local nonce=$(__nonce)

	local auth=("oauth_consumer_key=${TWITTER_CONSUMER_KEY}"
	            "oauth_token=${TWITTER_AUTH_TOKEN}"
	            "oauth_signature_method=HMAC-SHA1"
	            "oauth_version=1.0"
	            "oauth_timestamp=${timestamp}"
	            "oauth_nonce=${nonce}")

	local sigParams=("$@" "${auth[@]}")

	local sigBase=$(__signature_base "POST" "${baseUri}" "${sigParams[@]}")
	local signature=$(__sign "${sigBase}" "${sigKey}")

	local auth=("${auth[@]}" "oauth_signature=${signature}")

	local request="curl -s"
	if [ "$#" -gt 0 ]; then
		request="${request} -d $(echo -n "$@" | perl -pe 's/\s+$//' | perl -pe 's/\s+/ -d /g')"
	fi

	local authString=""
	for authParam in ${auth[@]}; do
		local authParam=($(echo -n $authParam | perl -pe 's/=/ /'))
		local authKey="${authParam[0]}"
		local authValue="$(__url_encode ${authParam[1]})"
		authString="${authString}$authKey=\"$authValue\", "
	done

	## tmpFile usage to get around command line length
	tmpFile=$(mktemp /tmp/twitter.auth.XXXXXX)
	echo -n "Authorization: OAuth $authString" | perl -pe 's/[, ]+$//g' | perl -pe 's/ /\\\ /g' > $tmpFile
	local response=$(cat $tmpFile | xargs -I {} ${request} -H {} ${baseUri})
	rm -f $tmpFile

	local updateId=$(echo "$response" | perl -pe 's/^{.*?"id_str"\s*:\s*"([^"]*)".*?}$/$1/i')

	if [ "$updateId" = "$response" ]; then
		echo "$response" | perl -pe 's/^.*?(?:"error"\s*:\s*"([^"]*)").*?$/$1/i' | perl -pe 's/([^\\])\\/$1/g' >&2
		return 1
	fi

	echo "$updateId"
}

function twitter_update {
	local twitter_error=0

	if [ -z "$TWITTER_CONSUMER_KEY" ]; then
		echo "Unable to find TWITTER_CONSUMER_KEY" >&2
		twitter_error=2
	elif [ -z "$TWITTER_CONSUMER_SECRET" ]; then
		echo "Unable to find TWITTER_CONSUMER_SECRET" >&2
		twitter_error=3
	elif [ -z "$TWITTER_AUTH_TOKEN" ]; then
		echo "Unable to find TWITTER_AUTH_TOKEN" >&2
		twitter_error=4
	elif [ -z "$TWITTER_AUTH_SECRET" ]; then
		echo "Unable to find TWITTER_AUTH_SECRET" >&2
		twitter_error=5
	elif [ -z "$@" ]; then
		echo "Status not provided" >&2
		twitter_error=6
	elif [ "${#@}" -gt 140 ]; then
		echo "Status is too long" >&2
		twitter_error=7
	fi

	if [ "$twitter_error" -ge 1 ]; then
		return $twitter_error
	fi

	__do_request "http://api.twitter.com/1/statuses/update.json" "status=$(__url_encode "$@")"

	return $?
}

if [ "$BASH_SOURCE" == "$0" ]; then
	twitter_update "$@"
fi