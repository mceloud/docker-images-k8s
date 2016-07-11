#!/bin/bash -e

[[ "$DEBUG" =~ ^(True|true|1|yes)$ ]] && set -x

TAG_PREFIX=${TAG_PREFIX:-tcpcloud}
TAG_VERSION=${TAG_VERSION:-latest}
BUILD_PATH=${*:-"k8s-base.dockerfile services"}
BUILD_ARGS=${BUILD_ARGS:-""}
BUILD_ARGS_SALT_BASE=${BUILD_ARGS_SALT_BASE:-""}
MAX_JOBS=${JOBS:-1}

JOBS=()
RETVAL=0

build_image() {
    name=$(echo $(basename $1 .dockerfile) | sed 's,\.,-,g')
    echo "== Building $name"
    stdbuf -oL -eL docker build --no-cache -t ${TAG_PREFIX}/${name}:${TAG_VERSION} $BUILD_ARGS -f $1 . 2>&1 | stdbuf -oL -eL tee log/${name}.log
    docker tag ${TAG_PREFIX}/${name}:${TAG_VERSION} ${TAG_PREFIX}/${name}:latest
}

wait_jobs() {
    echo "== Waiting for jobs: ${JOBS[@]}"
    for job in ${JOBS[@]}; do
        wait $job
    done
    JOBS=()
}

cleanup() {
    set +e
    echo "== Cleaning up jobs: ${JOBS[@]}"
    for job in ${JOBS[@]}; do
        kill $job
    done
    exit $RETVAL
}

trap cleanup EXIT

[ ! -d log ] && mkdir log || rm -f log/*.log

BUILD_ARGS="${BUILD_ARGS} ${BUILD_ARGS_SALT_BASE}" build_image k8s-base.dockerfile

DOCKERFILES=$(find $BUILD_PATH -name "*.dockerfile" | grep -v k8s-base.dockerfile)
for service in ${DOCKERFILES[@]}; do
    if [[ $service =~ *k8s-base* ]]; then
        continue
    fi

    if [ ${#JOBS[@]} -ge $MAX_JOBS ]; then
        wait_jobs
    fi

    build_image $service &
    JOBS+=($!)
done

wait_jobs
echo

for log_file in log/*.log; do
    if [ -z "$(grep "Successfully built " $log_file 2>/dev/null)" ]; then
        echo "== Build of $(basename $log_file .log) failed" 1>&2
        RETVAL=1
    fi
done

exit $RETVAL
