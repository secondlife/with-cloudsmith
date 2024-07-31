#!/usr/bin/env bats

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  # Make repository root available to PATH
  DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  PATH="$DIR/..:$PATH"

  # Clear any cloudsmith variables from the user environment
  export CLOUDSMITH_TOKEN=
  export CLOUDSMITH_API_KEY=
  export CLOUDSMITH_USER=
  export CLOUDSMITH_PASSWORD=

  # Set repo and org so that they don't need to be passed in as args
  export CLOUDSMITH_ORG=org
  export CLOUDSMITH_REPO=repo

  # Operate out of temp dir
  export TMPDIR="$(mktemp -d)"
  export WITH_CLOUDSMITH_ROOT="$TMPDIR"

  # Always source with-cloudsmith so we can test individual functions
  source with-cloudsmith

  # Source helpers
  source "$BATS_TEST_DIRNAME/fixtures.sh"

  # Stub curl, providing  response to the /v1/self API endpoint
  function curl { echo '{"slug": "test-user"}'; }
  export -f curl

  # Stub apt-get
  function apt-get { echo ""; }
  export -f apt-get

  # Provide a default /etc/os-release
  create_osrelease "$BOOKWORM_OS_RELEASE"
}

teardown() {
  rm -r "$TMPDIR"
}

setup_deb_mocks() {
  # Provide user so that a API call to /v1/user/self/ is not made
  export CLOUDSMITH_USER="test-user"
  export CLOUDSMITH_API_KEY="test-api-key"

  # Stub response to /v1/repos/ORG/REPO/gpg/
  function curl {
    echo '{"public_key": "PUBLIC KEY"}'
  }
  export -f curl

  # Stub gpg
  function gpg {
    touch "$TMPDIR/etc/apt/keyrings/org-repo.gpg"
  }
  export -f gpg
}

create_osrelease() {
  mkdir -p "$TMPDIR/etc"
  echo "$1" > "$TMPDIR/etc/os-release"
}

@test "runs without a command" {
  run with-cloudsmith
  assert_success
}

@test "runs silently when passed -s" {
  run with-cloudsmith -s
  assert_success
  assert_output ""
}

@test "informs user when setup skipped" {
  run with-cloudsmith
  assert_success
  [ "$output" = "Skipping Cloudsmith setup (no credentials)" ]
}

@test "runs subcommand" {
  run with-cloudsmith -s echo "foo"
  assert_success
  assert_output "foo"
}

@test "returns exit code of subcommand" {
  bats_require_minimum_version 1.5.0
  run -127 with-cloudsmith exit 127
  assert_equal "$status" "127"
}

@test "requires --org" {
  export CLOUDSMITH_ORG=
  run with-cloudsmith
  assert_failure
  assert_output "No organization (-o|--org) specified"
}

@test "requires --repo" {
  export CLOUDSMITH_REPO=
  run with-cloudsmith
  assert_failure
  assert_output "No repository (-r|--repo) specified"
}

@test "can pass org and repo as arguments" {
  export CLOUDSMITH_REPO=
  export CLOUDSMITH_ORG=
  run with-cloudsmith -r repo -o org
  assert_success
}

@test "json_value returns value" {
  run json_value key '{"key": "value"}'
  assert_success
  assert_output "value"
}

@test "json_value returns nothing if there is no matching key" {
  run json_value missing '{"key": "value"}'
  assert_success
  assert_output ""
}

@test "os_codename finds the right name (jessie)" {
  create_osrelease "$JESSIE_OS_RELEASE"
  run os_codename
  echo "output=$output"
  assert_success
  assert_output "jessie"
}

@test "os_codename finds the right name (bookworm)" {
  create_osrelease "$BOOKWORM_OS_RELEASE"
  run os_codename
  assert_success
  assert_output "bookworm"
}

@test "os_codename finds the right name (focal)" {
  create_osrelease "$FOCAL_OS_RELEASE"
  run os_codename
  assert_success
  assert_output "focal"
}

@test "os_id finds the right id (jessie)" {
  create_osrelease "$JESSIE_OS_RELEASE"
  run os_id
  assert_success
  assert_output "debian"
}

@test "os_id finds the right id (bookworm)" {
  create_osrelease "$BOOKWORM_OS_RELEASE"
  run os_id
  assert_success
  assert_output "debian"
}

@test "os_id finds the right id (focal)" {
  create_osrelease "$FOCAL_OS_RELEASE"
  run os_id
  assert_success
  assert_output "ubuntu"
}

@test "os_codename returns nothing if there is no os-release file" {
  run os_codename /tmp/does-not-exist
  assert_success
  assert_output ""
}

@test "credentials are loaded from /run/secrets" {
  mkdir -p "$TMPDIR/run/secrets"
  echo "test-api-key" > $TMPDIR/run/secrets/CLOUDSMITH_API_KEY
  run with-cloudsmith -s bash -c 'echo $CLOUDSMITH_API_KEY'
  assert_output "test-api-key"
  assert_success
}

@test "credentials are loaded from /run/secrets/cloudsmith (ini)" {
  mkdir -p "$TMPDIR/run/secrets"
  echo -e "[default]\napi_key=test-api-key" > "$TMPDIR/run/secrets/cloudsmith"
  run with-cloudsmith -s bash -c 'echo $CLOUDSMITH_API_KEY'
  assert_output "test-api-key"
  assert_success
}

@test "credentials are loaded from /run/secrets/cloudsmith (source)" {
  mkdir -p "$TMPDIR/run/secrets"
  echo "CLOUDSMITH_API_KEY=test-api-key" > "$TMPDIR/run/secrets/cloudsmith"
  run with-cloudsmith -s bash -c 'echo $CLOUDSMITH_API_KEY'
  assert_output "test-api-key"
  assert_success
}

@test "credentials are loaded from credentials.ini" {
  mkdir -p "$TMPDIR$HOME/.cloudsmith"
  echo -e "[default]\napi_key=test-api-key" > "$TMPDIR$HOME/.cloudsmith/credentials.ini"
  run with-cloudsmith -s bash -c 'echo $CLOUDSMITH_API_KEY'
  assert_output "test-api-key"
  assert_success
}

@test "CLOUDSMITH_USER loaded if CLOUDSMITH_API_KEY provided" {
  export CLOUDSMITH_API_KEY="test-api-key"
  run with-cloudsmith -s bash -c 'echo $CLOUDSMITH_USER'
  assert_success
  assert_output "test-user"
}

@test "GPG key is installed into /etc/apt/keyrings" {
  setup_deb_mocks
  run with-cloudsmith --deb --keep
  assert_success
  [ -f $TMPDIR/etc/apt/keyrings/org-repo.gpg ]
}

@test "deb sources are set up" {
  setup_deb_mocks
  run with-cloudsmith --deb --keep
  assert_success
  [ -f $TMPDIR/etc/apt/sources.list.d/org-repo.list ]
  [ -f $TMPDIR/etc/apt/auth.conf.d/org-repo.conf ]
}

@test "deb sources are cleaned up" {
  setup_deb_mocks
  run with-cloudsmith --deb
  assert_success
  [ ! -f $TMPDIR/etc/apt/sources.list.d/org-repo.list ]
  [ ! -f $TMPDIR/etc/apt/auth.conf.d/org-repo.conf ]
  [ ! -f $TMPDIR/etc/apt/keyrings/org-repo.gpg ]
}

@test "basic auth is included in deb sources on older debian versions" {
  setup_deb_mocks
  create_osrelease "$JESSIE_OS_RELEASE"
  run with-cloudsmith --deb --keep
  assert_success
  list="$(< $TMPDIR/etc/apt/sources.list.d/org-repo.list)"
  [ -f $TMPDIR/etc/apt/sources.list.d/org-repo.list ]
  [ ! -f $TMPDIR/etc/apt/auth.conf.d/org-repo.conf ]
  [[ "$list" =~ "test-user:test-api-key@dl.cloudsmith.io" ]]
}

@test "pip.conf is set up" {
  export CLOUDSMITH_API_KEY="test-api-key"
  run with-cloudsmith --pip --keep
  assert_success
  [ -f $TMPDIR/etc/pip.conf ]
}

@test "pip.conf is cleaned up" {
  export CLOUDSMITH_API_KEY="test-api-key"
  run with-cloudsmith --pip
  assert_success
  [ ! -f $TMPDIR/etc/pip.conf ]
}

@test "existing pip.conf is restored" {
  export CLOUDSMITH_API_KEY="test-api-key"
  echo "old" > $TMPDIR/etc/pip.conf
  run with-cloudsmith --pip
  assert_success
  assert_equal "$(<$TMPDIR/etc/pip.conf)" "old"
}

@test "composer auth.json is set up" {
  export CLOUDSMITH_API_KEY="test-api-key"
  run with-cloudsmith --composer --keep
  assert_success
  [ -f $TMPDIR$HOME/.config/composer/auth.json ]
}

@test "composer auth.json is cleaned up" {
  export CLOUDSMITH_API_KEY="test-api-key"
  run with-cloudsmith --composer
  assert_success
  [ ! -f $TMPDIR$HOME/.config/composer/auth.json ]
}

@test "existing composer auth.json is restored" {
  export CLOUDSMITH_API_KEY="test-api-key"
  mkdir -p "$TMPDIR$HOME/.config/composer"
  echo "old" > $TMPDIR$HOME/.config/composer/auth.json
  run with-cloudsmith --composer
  assert_success
  assert_equal "$(<$TMPDIR$HOME/.config/composer/auth.json)" "old"
}
