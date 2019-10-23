#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${0}")/teamcity-support.sh"

tc_prepare

export TMPDIR=$PWD/artifacts/testrace
mkdir -p "$TMPDIR"

tc_start_block "Determine changed packages"
pkgspec=./pkg/...
echo "On release branch ($TC_BUILD_BRANCH), so running testrace on all packages ($pkgspec)"
tc_end_block "Determine changed packages"

tc_start_block "Compile C dependencies"
# Buffer noisy output and only print it on failure.
run build/builder.sh make -Otarget c-deps GOFLAGS=-race &> artifacts/race-c-build.log || (cat artifacts/race-c-build.log && false)
rm artifacts/race-c-build.log
tc_end_block "Compile C dependencies"

tc_start_block "Maybe stressrace pull request"
build/builder.sh go install ./pkg/cmd/github-pull-request-make
build/builder.sh env BUILD_VCS_NUMBER="$BUILD_VCS_NUMBER" TARGET=stressrace github-pull-request-make
tc_end_block "Maybe stressrace pull request"

# Expect the timeout to come from the TC environment.
TESTTIMEOUT=${TESTTIMEOUT:-45m}

tc_start_block "Run Go tests under race detector"
true >artifacts/testrace.log
for pkg in $pkgspec; do
	run build/builder.sh env \
		COCKROACH_LOGIC_TESTS_SKIP=true \
		stdbuf -oL -eL \
		make testrace \
		PKG="$pkg" \
		TESTTIMEOUT=$TESTTIMEOUT \
		TESTFLAGS="-v $TESTFLAGS" \
		ENABLE_ROCKSDB_ASSERTIONS=1 2>&1 \
		ENABLE_LIBROACH_ASSERTIONS=1 2>&1 \
		| tee -a artifacts/testrace.log \
		| go-test-teamcity
done
tc_end_block "Run Go tests under race detector"
