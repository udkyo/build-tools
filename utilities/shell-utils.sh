function chk_set {
    var=$1
    # ${!var} is a little-known bashism that says "expand $var and then
    # use that as a variable name and expand it"
    if [[ -z "${!var}" ]]; then
        echo "\$${var} must be set!"
        exit 1
    fi
}

function error {
    if [ "${ERRORS}" != "" ]
    then
        ERRORS="${ERRORS}${FUNCNAME[1]}: ${1}\n"
    else
        ERRORS="${FUNCNAME[1]}: ${1}\n"
    fi
}

function tag_release {
    if [ ${#} -ne 3 ]
    then
        error "expected [product] [version] [build_number], got ${@}"
    fi
    local PRODUCT=$1
    local VERSION=$2
    local BLD_NUM=$3

    mkdir manifest
    pushd manifest
    curl --fail -LO http://latestbuilds.service.couchbase.com/builds/latestbuilds/${PRODUCT}/${VERSION}/${BLD_NUM}/${PRODUCT}-${VERSION}-${BLD_NUM}-manifest.xml
    git init
    git add ${PRODUCT}-${VERSION}-${BLD_NUM}-manifest.xml
    git commit -am "Add manifest"
    popd

    repo init -u ./manifest -m ${PRODUCT}-${VERSION}-${BLD_NUM}-manifest.xml
    repo sync -j8

    COMMIT=$(xmllint --xpath "string(//project[@name=\"${PRODUCT}\"]/@revision)" manifest/${PRODUCT}-${VERSION}-${BLD_NUM}-manifest.xml)

    pushd "${PRODUCT}"
    if [ "${COMMIT}" = "" ]
    then
        error "Got empty revision from manifest, couldn't tag release"
    elif ! test $(git cat-file -t ${COMMIT}) == commit
    then
        error "Expected to find a commit, found a $(git cat-file -t ${COMMIT}) instead"
    else
        if git tag | grep "${VERSION}" &>/dev/null
        then
            error "Tag ${VERSION} already exists, please investigate ($(git rev-parse -n1 ${VERSION}))"
        else
            git remote add gerrit "ssh://review.couchbase.org:29418/${PRODUCT}.git"
            git tag -a "${VERSION}" "${COMMIT}" -m "Version ${VERSION}"
            git push gerrit ${VERSION}
        fi
    fi
    popd
}
