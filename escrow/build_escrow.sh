#!/bin/bash
set -ex
source ./escrow_config || exit 1

# Top-level directory; everything to escrow goes in here.
if [ -z "$1" ]
then
  echo "Usage: $0 /path/to/output/files"
  exit 1
fi

# Make sure we're using an absolute path
mkdir -p $1
pushd $1
ROOT=$(pwd)
popd

ESCROW="${ROOT}/${PRODUCT}-${VERSION}"
mkdir -p "${ESCROW}/deps"

if [[ "$OSTYPE" == "darwin"* ]]
then
  OS=darwin
else
  OS=linux
fi

heading() {
  echo
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo "$@"
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo
}

fatal() {
  echo "FATAL: $@"
  exit 1
}

cache_deps() {
  # Parses tlm/deps/manifest.cmake, downloading each package
  # to ${ESCROW}/deps/.cbdepscache
  echo "# Patch: Caching deps"

  local cache=${ESCROW}/deps/.cbdepscache
  mkdir -p $cache || :
  pushd $cache

  for platform in ${PLATFORMS}
  do
    echo "platform: ${platform}"
    # for dependency in ${CACHED_DEPS[@]}
    # do
      if [ "${platform}" = "ubuntu18" ]
      then
        platform="ubuntu18.04"
      elif [ "${platform}" = "ubuntu16" ]
      then
        platform="ubuntu16.04"
      elif [ "${platform}" = "ubuntu20" ]
      then
        platform="ubuntu20.04"
      fi
      urls=$(awk "/^DECLARE_DEP.*$platform/ {
        if(\$4 ~ /VERSION/) {
          url = \"https://packages.couchbase.com/couchbase-server/deps/\" substr(\$2,2) \"/\" \$5 \"/\" \$7 \"/\" substr(\$2,2) \"-${platform}-x86_64-\" \$5 \"-\" \$7;
          print url \".md5\";
          print url \".tgz\";
        } else {
          url = \"https://packages.couchbase.com/couchbase-server/deps/\" substr(\$2,2) \"/\" \$4 \"/\" substr(\$2,2) \"-${platform}-x86_64-\" \$4;
          print url \".md5\";
          print url \".tgz\";
        }
      }" "${ESCROW}/src/tlm/deps/manifest.cmake")
      for url in $urls
      do
        if [ ! -f "$(basename $url)" ]; then
          echo "Fetching $url"
          curl -fO "$url" \
            || fatal "Package download failed"
        else
          echo "$(basename $url) already present"
        fi
      done
  done
  popd
}

cache_analytics() {
  echo "# Caching analytics"
  VERSION_STRINGS=$(awk "/PACKAGE analytics-jars VERSION/ {print substr(\$5, 1, length(\$5)-1)}" "${ESCROW}/src/analytics/CMakeLists.txt") || fatal "Coudln't get analytics version"
  if [ -z "$VERSION_STRINGS" ]
  then
    fatal "Failed to retrieve analytics versions"
  fi
  for version in $VERSION_STRINGS
  do
    if [[ $version == \$\{*\} ]]; # if it's a parameter, we need to figure out what its value is
    then
      param=${version:2:${#version}-3}
      _v=$(grep "SET ($param " "${ESCROW}/src/analytics/CMakeLists.txt" | cut -d'"' -f2)
    else
      _v=$version
    fi
    analytics_version=$(echo $_v | sed 's/-.*//')
    analytics_build=$(echo $_v | sed 's/.*-//')

    if [ ! -f "${ESCROW}/deps/.cbdepscache/analytics-jars-${analytics_version}-${analytics_build}.tar.gz" ]
    then
      (
        # .cbdepscache gets copied into the build container - this target is a
        # convenience to make sure the files are available later
        cd ${ESCROW}/deps/.cbdepscache
        curl --fail -LO https://packages.couchbase.com/releases/${analytics_version}/analytics-jars-${analytics_version}-${analytics_build}.tar.gz
      )
    fi
  done

  mkdir -p ${ESCROW}/src/analytics/cbas/cbas-install/target/cbas-install-1.0.0-SNAPSHOT-generic/cbas/repo/compat/60x
}

cache_openjdk() {
  echo "# Caching openjdk"

  local openjdk_versions=$(awk '/SET \(_jdk_ver / {print substr($3, 1, length($3)-1)}' ${ESCROW}/src/analytics/cmake/Modules/FindCouchbaseJava.cmake) \
    || fatal "Couldn't get openjdk versions"
  echo "openjdk_versions: $openjdk_versions"
  for openjdk_version in $openjdk_versions
  do
    "${ESCROW}/deps/cbdep-${cbdep_ver_latest}-${OS}" -p linux install -d ${ESCROW}/deps/.cbdepscache -n openjdk "${openjdk_version}" || fatal "OpenJDK install failed"
  done
}

copy_cbdepcache() {
  if [ "${OS}" = "linux" ]; then cp -rp ~/.cbdepcache/* ${ESCROW}/deps/.cbdepcache; fi
}

copy_container_images() {
  # Save copies of all Docker build images
  heading "Saving Docker images..."
  mkdir -p "${ESCROW}/docker_images" 2>/dev/null || :
  pushd "${ESCROW}/docker_images"
  for img in ${IMAGES}
  do
    heading "Saving Docker image ${img}"
    if [ "$(docker image ls -q ${img})" == "" ]
    then
      echo "... Pulling ${img}..."
      docker pull "${img}"
    else
      echo "... Image already pulled"
    fi

    output=$(basename "${img}").tar.gz
    if [ ! -f ${output} ]
    then
      echo "... Saving local copy of ${img}..."
      if [ ! -s "${output}" ]
      then
        docker save "${img}" | gzip > "${output}"
      fi
    else
      echo "... Local copy already exists (${output})"
    fi
  done
  popd
}

get_build_manifests_repo() {
  heading "Downloading build-manifests ..."
  pushd "${ESCROW}"
  if [ ! -d build-manifests ]
  then
    git clone git://github.com/couchbase/build-manifests.git
  else
    (cd build-manifests && git fetch origin master)
  fi
  popd
}

get_cbdeps_versions() {
  # Interrogate CBDownloadDeps and curl_unix.sh style build scripts to generate a deduplicated array
  # of cbdeps versions.
  local versions=$(find "${1}/build-manifests/python_tools/cbdep" -name "*.xml" |  grep -Eo "[0-9\.]+.xml" | sed 's/\.[^.]*$//')
  versions=$(echo $versions | tr ' ' '\n' | sort -uV | tr '\n' ' ')
  echo $versions
}

# Retrieve list of current Docker image/tags from stackfile
stackfile=$(curl -L --fail https://raw.githubusercontent.com/couchbase/build-infra/master/docker-stacks/couchbase-server/server-jenkins-buildslaves.yml)

# Retrieve list of platform - these correspond to the available Docker buildslave images for a given release.
PLATFORMS=$(python3 - <<EOF
import yaml

stack = yaml.safe_load("""${stackfile}""")

platforms = list()

def get_labels(env):
    for line in env:
      if line.startswith('JENKINS_SLAVE_LABELS='):
        return line.replace('JENKINS_SLAVE_LABELS=', '').split(' ')

for name, service in stack['services'].items():
    if '${RELEASE}' in get_labels(service['environment']):
        distro = name.replace('-clang9','').replace('-${RELEASE}', '')
        if distro not in ['suse11', 'suse12']:
            platforms.append(distro)

print(' '.join(platforms))
EOF
)

IMAGES=$(python3 - <<EOF
import yaml

stack = yaml.safe_load("""${stackfile}""")
distros = "${PLATFORMS}"

for distro in distros.split():
    print(stack['services'][distro]['image'])
EOF
)

# Get the source code
heading "Downloading released source code for ${PRODUCT} ${VERSION}..."
mkdir -p "${ESCROW}/src"
pushd "${ESCROW}/src"
git config --global user.name "Couchbase Build Team"
git config --global user.email "build-team@couchbase.com"
git config --global color.ui false
repo init -u git://github.com/couchbase/manifest -g all -m "${MANIFEST_FILE}"
repo sync --jobs=6
get_build_manifests_repo
popd

# Get cbdeps binaries
CBDEPS_VERSIONS="$(get_cbdeps_versions "${ESCROW}")"
heading "Downloading cbdep versions: ${CBDEPS_VERSIONS}"
for cbdep_ver in ${CBDEPS_VERSIONS}
do
  if [ ! -f "${ESCROW}/deps/cbdep-${cbdep_ver}-linux" ]
  then
    curl --fail -o "${ESCROW}/deps/cbdep-${cbdep_ver}-linux" "https://packages.couchbase.com/cbdep/${cbdep_ver}/cbdep-${cbdep_ver}-linux"
    chmod +x "${ESCROW}/deps/cbdep-${cbdep_ver}-linux"
  fi
done
cbdep_ver_latest=$(echo ${CBDEPS_VERSIONS} | tr ' ' '\n' | tail -1)

# Get go versions
GOVERS="$(echo $(find "${ESCROW}" -name CMakeLists.txt | xargs cat | awk '/GOVERSION [0-9]/ {print $2}' | grep -Eo "[0-9\.]+") | tr ' ' '\n' | sort -u | tr '\n' ' ') $EXTRA_GOLANG_VERSIONS"
heading "Downloading Go installers: ${GOVERS}"
mkdir -p "${ESCROW}/golang"
pushd "${ESCROW}/golang"
for gover in ${GOVERS}
do
  echo "... Go ${gover}..."
  gofile="go${gover}.linux-amd64.tar.gz"
  if [ ! -e "${gofile}" ]
  then
    curl -o "${gofile}" "http://storage.googleapis.com/golang/${gofile}"
  fi
done
popd

heading "Copying build scripts into escrow..."
cp -a ./escrow_config templates/* patches.sh "${ESCROW}/"
perl -pi -e "s/\@\@VERSION\@\@/${VERSION}/g; s/\@\@PLATFORMS\@\@/${PLATFORMS}/g; s/\@\@CBDEPS_VERSIONS\@\@/${CBDEPS_VERSIONS}/g;" \
  "${ESCROW}/README.md" "${ESCROW}/build-couchbase-server-from-escrow.sh" "${ESCROW}/patches.sh" "${ESCROW}/in-container-build.sh"

cache_deps
# OpenJDK must be handled after analytics as analytics cmake is interrogated for SDK version
cache_analytics
cache_openjdk

copy_cbdepcache
copy_container_images

echo "Downloading rsync to ${ESCROW}/deps/rsync"
curl -fLo "${ESCROW}/deps/rsync" https://github.com/JBBgameich/rsync-static/releases/download/continuous/rsync-x86

heading "Done!"
