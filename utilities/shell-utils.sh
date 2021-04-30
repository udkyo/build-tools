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
    if [ ${#} -ne 2 ]
    then
        error "expected [product] [version], got ${@}"
    fi
    local PRODUCT=$1
    local VERSION=$2

    COMMIT=$(xmllint --xpath "string(//project[@name=\"${PRODUCT}\"]/@revision)" manifest.xml)

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
            git tag "${VERSION}" "${COMMIT}"
            git push origin "${VERSION}"
        fi
    fi
    popd
}
