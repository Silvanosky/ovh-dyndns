#!/bin/bash

# DEFAULT CONFIG
LIBS="libs"
GET_IP_URL="https://api.ipify.org/"
GET_IP6_URL="https://api6.ipify.org"
CURRENT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_TARGET="EU"

help()
{
    echo
    echo "Help: possible arguments are:"
    echo "  --domain <domain>       : the domain on which update the A record in the DNS zone"
    echo "  --subdomain <subdomain> : (optional) the subdomain for this A record"
    echo
}

checkInternetConnexion()
{
    ping -c1 -w2 1.1.1.1 &> /dev/null
    if [ $? -ne 0 ]
    then
        exit 2
    fi
}

requestApi()
{
    URL=$1
    METHOD=$2
    DATA=$3

    PARAMS=("--target")
    PARAMS+=("$API_TARGET")

    PARAMS+=("--url")
    PARAMS+=("$URL")

    if [ "$METHOD" ]
    then
        PARAMS+=("--method")
        PARAMS+=("$METHOD")
    fi

    if [ "$DATA" ]
    then
        PARAMS+=("--data")
        PARAMS+=("$DATA")
    fi
    RESPONSE=$( $CURRENT_PATH/ovh-api-bash-client.sh "${PARAMS[@]}" )
    HTTP_STATUS="$( echo $RESPONSE | cut -d' ' -f1 )"
    HTTP_RESPONSE="$( echo $RESPONSE | cut -d' ' -f2- )"
    echo $HTTP_STATUS
}

updateIp()
{
    IP=$(wget -q -O - $GET_IP_URL)
    IP6=$(wget -q -O - $GET_IP6_URL)
}

getJSONString()
{
    JSON="$1"
    FIELD="$2"
    RESULT=$(getJSONValue "$JSON" "$FIELD")
    echo ${RESULT:1:-1}
}

getJSONValue()
{
    JSON="$1"
    FIELD="$2"
    RESULT=$(echo $JSON | $CURRENT_PATH/$LIBS/JSON.sh -l | grep "\[$FIELD\]" | sed -r "s/\[$FIELD\]\s+(.*)/\1/")
    echo ${RESULT}
}

getJSONArrayLength()
{
    JSON="$1"
    echo $JSON | $CURRENT_PATH/$LIBS/JSON.sh -l | wc -l
}

parseArguments()
{
    while [ $# -gt 0 ]
    do
        case $1 in
        --domain)
            shift
            DOMAIN=$1
            ;;
        --subdomain)
            shift
            SUBDOMAIN=$1
            ;;
        esac
        shift
    done
}

checkArgumentsValids()
{
    if [ -z $DOMAIN ]
    then
        echo "No domain given"
        help
        exit 1
    fi
}

refreshZone()
{
    requestApi "/domain/zone/$DOMAIN/refresh" 'POST' > /dev/null
}

getIds ()
{
    requestApi "/domain/zone/$DOMAIN/record?subDomain=$SUBDOMAIN&fieldType=A" > /dev/null
    if [ $HTTP_STATUS -ne 200 ]
    then
        echo "Error: $HTTP_STATUS $HTTP_RESPONSE"
        exit 1
    fi
    IDS="$HTTP_RESPONSE"

    requestApi "/domain/zone/$DOMAIN/record?subDomain=$SUBDOMAIN&fieldType=AAAA" > /dev/null
    if [ $HTTP_STATUS -ne 200 ]
    then
        echo "Error: $HTTP_STATUS $HTTP_RESPONSE"
        exit 1
    fi
    IDS6="$HTTP_RESPONSE"
}

main()
{
    parseArguments "$@"
    checkArgumentsValids
    checkInternetConnexion

    updateIp
    getIds

	#IPV4
    if [ $(getJSONArrayLength $IDS) -gt 1 ]
    then
        echo "Error, multiple results found for record"
        echo "$IDS"
        i=0
        while [ $i -lt $(getJSONArrayLength $IDS) ]
        do
            CURRENT_ID=$(getJSONValue $IDS $i)
            requestApi "/domain/zone/$DOMAIN/record/$CURRENT_ID" 'DELETE' > /dev/null
            i=$((i+1))
        done
        echo "All results were deleted, will create a new record"
        getIds
    fi

	#IPV6
    if [ $(getJSONArrayLength $IDS6) -gt 1 ]
    then
        echo "Error, multiple results found for record"
        echo "$IDS6"
        i=0
        while [ $i -lt $(getJSONArrayLength $IDS6) ]
        do
            CURRENT_ID=$(getJSONValue $IDS6 $i)
            requestApi "/domain/zone/$DOMAIN/record/$CURRENT_ID" 'DELETE' > /dev/null
            i=$((i+1))
        done
        echo "All results were deleted, will create a new record"
        getIds
    fi

	#IPV4
    if [ $(getJSONArrayLength $IDS) -eq 0 ]
    then
        # No record found, create one
        requestApi "/domain/zone/$DOMAIN/record" 'POST' '{"target": "'$IP'", "subDomain": "'$SUBDOMAIN'", "fieldType": "A", "ttl": 60}' > /dev/null
        refreshZone
        exit 0
    fi

	#IPV6
	if [ $(getJSONArrayLength $IDS6) -eq 0 ]
    then
        # No record found, create one
        requestApi "/domain/zone/$DOMAIN/record" 'POST' '{"target": "'$IP6'", "subDomain": "'$SUBDOMAIN'", "fieldType": "AAAA", "ttl": 60}' > /dev/null
        refreshZone
        exit 0
    fi


	#IPV4
    RECORD=$(getJSONValue $IDS '0')
    requestApi "/domain/zone/$DOMAIN/record/$RECORD" > /dev/null
    if [ $HTTP_STATUS -ne 200 ]
    then
        echo "Error: $HTTP_STATUS $HTTP_RESPONSE"
        exit 1
    fi
    RECORD_IP=$(getJSONString $HTTP_RESPONSE '"target"')

    if [ $IP != $RECORD_IP ]
    then
        requestApi "/domain/zone/$DOMAIN/record/$RECORD" 'PUT' '{"target":"'$IP'", "ttl": 60}' > /dev/null
        refreshZone
    fi

	#IPV6
	RECORD6=$(getJSONValue $IDS6 '0')
    requestApi "/domain/zone/$DOMAIN/record/$RECORD6" > /dev/null
    if [ $HTTP_STATUS -ne 200 ]
    then
        echo "Error: $HTTP_STATUS $HTTP_RESPONSE"
        exit 1
    fi
    RECORD_IP6=$(getJSONString $HTTP_RESPONSE '"target"')

    if [ $IP6 != $RECORD_IP6 ]
    then
        requestApi "/domain/zone/$DOMAIN/record/$RECORD6" 'PUT' '{"target":"'$IP6'", "ttl": 60}' > /dev/null
        refreshZone
    fi
}


main "$@"

