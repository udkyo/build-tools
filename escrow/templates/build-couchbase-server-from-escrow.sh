#!/bin/bash
set -ex

# These platforms correspond to the available Docker worker images.
PLATFORMS="amzn2 linux"

usage() {
  echo "Usage: $0 <platform>"
  echo "  where <platform> is one of: ${PLATFORMS}"
  exit 1
}

# Check input argument
if [ $# -eq 0 ]
then
  usage
fi
export PLATFORM=$1

container_workdir=/home/couchbase

sup=$(echo ${PLATFORMS} | egrep "\b${PLATFORM}\b" || true)
if [ -z "${sup}" ]
then
  echo "Unknown platform $1"
  usage
fi

# Ensure docker is present
docker version > /dev/null 2>&1
if [ $? -ne 0 ]
then
  echo "Docker is required to be installed!"
  exit 5
fi

heading() {
  echo
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo $*
  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
  echo
}

ROOT=`pwd`

# Load Docker worker image for desired platform
cd docker_images
IMAGE=couchbasebuild/$( basename -s .tar.gz $( ls server-${PLATFORM}* | head -1 ) )
if [[ -z "`docker images -q ${IMAGE}`" ]]
then
  heading "Loading Docker image ${IMAGE}..."
  gzip -dc server-${PLATFORM}* | docker load
fi

# Run Docker worker
WORKER="${PLATFORM}-worker"
cd ${ROOT}

set +e
docker inspect ${WORKER} > /dev/null 2>&1
if [ $? -ne 0 ]
then
  set -e
  heading "Starting Docker worker container..."
  # We specify external DNS (Google's) to ensure we don't find
  # things on our LAN. We also point packages.couchbase.com to
  # a bogus IP to ensure we aren't dependent on existing packages.
  docker run --name "${WORKER}" -d \
    --add-host packages.couchbase.com:8.8.8.8 \
    --dns 8.8.8.8 \
    "${IMAGE}" tail -f /dev/null
else
  docker start "${WORKER}"
fi
set -e

# Load local copy of escrowed source code into container
# Removed -t from docker exec command as Jenkins doesn't like it: the input device is not a TTY
if [[ ! -z ${WORKSPACE} ]]
then
  DOCKER_EXEC_OPTION='-i'
else
  DOCKER_EXEC_OPTION='-it'
fi

DOCKER_EXEC_OPTION="${DOCKER_EXEC_OPTION} -ucouchbase"

docker exec ${DOCKER_EXEC_OPTION} ${WORKER} mkdir -p ${container_workdir}/escrow

heading "Copying escrowed sources and dependencies into container"
docker cp ./deps/rsync-$(uname -m) ${WORKER}:/usr/bin/rsync
docker exec ${WORKER} chmod a+x /usr/bin/rsync
docker exec ${WORKER} mkdir -p ${container_workdir}/escrow
docker exec ${WORKER} rm -f ./src/godeps/src/github.com/google/flatbuffers/docs/source/CONTRIBUTING.md
for f in ./in-container-build.sh \
         ./escrow_config \
         ./.cbdepscache \
         ./golang \
         ./src; do
  docker cp $f ${WORKER}:${container_workdir}/escrow
done

docker cp ./.cbdepscache ${WORKER}:${container_workdir}

docker exec ${WORKER} chown -R couchbase:couchbase ${container_workdir}/escrow/in-container-build.sh ${container_workdir}/escrow/escrow_config

# Launch build process
heading "Running full Couchbase Server build in container..."
echo "docker exec ${DOCKER_EXEC_OPTION} ${WORKER} bash \
  ${container_workdir}/escrow/in-container-build.sh ${container_workdir} ${PLATFORM} @@VERSION@@"
docker exec ${DOCKER_EXEC_OPTION} ${WORKER} bash \
  ${container_workdir}/escrow/in-container-build.sh ${container_workdir} ${PLATFORM} @@VERSION@@

# And copy the installation packages out of the container.
heading "Copying installer binaries"

cd ..

for file in `docker exec ${WORKER} bash -c \
  "ls ${container_workdir}/escrow/src/*${PLATFORM}*"`
do
  docker cp ${WORKER}:${file} .
  localfile=`basename ${file}`
  mv ${localfile} ${localfile/-9999/}
done
