#!/bin/bash -x

usage() {
    cat << EOF
Notarize a Couchbase Server build
Usage: $0 -r RELEASE -v VERSION -b BLD_NUM
EOF
    exit 1
}

check_notarization_status() {
    request=$1

    XML_OUTPUT=$(
        xcrun altool --notarization-info ${request} \
        -u build-team@couchbase.com -p ${AC_PASSWORD} \
        --output-format xml \
        2>&1
    )
    if [ $? != 0 ]; then
        echo "Error checking on status for ${request} - will ignore and keep trying"
        return 1
    fi

    STATUS=$(
        echo "$XML_OUTPUT" | \
        xmllint --xpath '//dict[key/text() = "notarization-info"]/dict/key[text() = "Status"]/following-sibling::string[1]/text()' -
    )
    case ${STATUS} in
        success)
            echo "Request ${request} succeeded!"
            return 0
            ;;
        "in progress")
            echo "Request ${request} still in progress..."
            return 1
            ;;
        invalid)
            echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            echo "Request ${request} failed notarization!"
            echo "$XML_OUTPUT" | grep LogFileURL
            echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            return 2
            ;;
        *)
            echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            echo "Request ${request} had surprising status ${STATUS}, quitting..."
            echo "$XML_OUTPUT"
            echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            return 2
            ;;
    esac
}

while getopts 'r:v:b:' options; do
    case "$options" in
        r) RELEASE=${OPTARG};;
        v) VERSION=${OPTARG};;
        b) BLD_NUM=${OPTARG};;
        \?) usage;;
    esac
done

if [ -z "${RELEASE}" -o -z "${VERSION}" -o -z "${BLD_NUM}" ]; then
    usage
fi

DMG_URL_DIR=http://latestbuilds.service.couchbase.com/builds/latestbuilds/couchbase-server/${RELEASE}/${BLD_NUM}

DMGS=(couchbase-server-enterprise_${VERSION}-${BLD_NUM}-macos_x86_64-unnotarized.dmg couchbase-server-community_${VERSION}-${BLD_NUM}-macos_x86_64-unnotarized.dmg)

# Check files exist
for file in ${DMGS[*]}; do
    if curl --head --silent --fail ${DMG_URL_DIR}/${file} 2> /dev/null;
    then
        curl -O ${DMG_URL_DIR}/${file}
    else
        echo "${DMG_URL_DIR}/${file} does not exist. Aborting..."
        exit 1
    fi
done

# Check already notarized
declare -a UNNOTARIZED
for file in ${DMGS[*]}; do
    echo "Checking notarization of ${file}"
    if xcrun stapler validate ${file}; then
        echo "${file} is already notarized"
    else
        UNNOTARIZED+=( ${file} )
    fi
    echo
done

# Start notarization process
declare -a REQUESTS
for file in ${UNNOTARIZED[*]}; do
    echo "Starting notarization for ${file} (takes a few moments)"
    XML_OUTPUT=$(
        xcrun altool --notarize-app -t osx \
        -f ${file} \
        --primary-bundle-id com.couchbase.couchbase-server \
        -u build-team@couchbase.com -p ${AC_PASSWORD} \
        --output-format xml
    )
    if [ $? != 0 ]; then
        echo "Error running notarize command!"
        exit 1
    fi
    REQUEST_ID=$(
       echo "$XML_OUTPUT" | \
       xmllint --xpath '//dict[key/text() = "RequestUUID"]/string/text()' -
    )
    echo "Notarization started - request ID is ${REQUEST_ID}"
    REQUESTS+=( ${REQUEST_ID} )
    echo
done

# Wait for completion of all requests
while true; do
    for i in ${!REQUESTS[@]}; do
        check_notarization_status ${REQUESTS[$i]}
        case $? in
            0)
                # Success! Staple the ticket to the result
                echo =========================================
                echo "Stapling notarization ticket to ${UNNOTARIZED[$i]}"
                echo =========================================
                xcrun stapler staple ${UNNOTARIZED[$i]}
                notarized_file_name=`echo ${UNNOTARIZED[$i]} |sed "s/-unnotarized.dmg/.dmg/"`
                mv ${UNNOTARIZED[$i]} $notarized_file_name
                # Don't check this one anymore
                unset REQUESTS[$i]
                echo
                ;;
            1)
                # Need to keep checking this one
                ;;
            2)
                # Don't check and remember there was a failure
                unset REQUESTS[$i]
                export JOB_FAILED=1
                echo
                ;;
        esac
    done
    if [ ${#REQUESTS[@]} = 0 ]; then
        break
    fi
    echo "Waiting a minute to check again..."
    sleep 60
done

echo
echo =========================================
echo "All done!"
echo =========================================
if [ ! -z "${JOB_FAILED}" ]; then
    echo "Some jobs failed..."
    exit 1
fi
