#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

pass() {
    ((PASS++))
    green "  PASS: $1"
}

fail() {
    ((FAIL++))
    red "  FAIL: $1"
}

check_exit() {
    local got="$1" want="$2" label="$3"
    if [[ "$got" -eq "$want" ]]; then
        pass "$label"
    else
        fail "$label (expected exit $want, got $got)"
    fi
}

check_contains() {
    local output="$1" substr="$2" label="$3"
    if [[ "$output" == *"$substr"* ]]; then
        pass "$label"
    else
        fail "$label (output missing '$substr')"
    fi
}

# Create a fake usermod that rejects a specific flag but passes everything
# else through to the real binary.
#   $1 — flag to block (e.g. "-l" or "-d")
fake_usermod_script() {
    local block_flag="$1"
    cat <<WRAPPER
        umod=\$(command -v usermod)
        cp "\$umod" "\${umod}.real"
        {
            echo "#!/bin/sh"
            echo "for a in \\"\\\$@\\"; do [ \\"\\\$a\\" = \\"${block_flag}\\" ] && exit 1; done"
            echo "exec \\"\${umod}.real\\" \\"\\\$@\\""
        } > "\$umod"
        chmod +x "\$umod"
WRAPPER
}

run_tests() {
    local distro="$1"
    local image="chusername-test-${distro}"

    echo ""
    echo "=== ${distro} ==="
    echo ""

    echo "Building image..."
    if ! docker build -t "$image" -f "${SCRIPT_DIR}/${distro}/Dockerfile" "$PROJECT_DIR" > /dev/null 2>&1; then
        fail "build ${distro} image"
        return
    fi
    pass "build image"

    # --- wrong arg count ---
    echo "[wrong arg count]"
    output=$(docker run --rm "$image" /chusername.sh 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "usage" "prints usage"

    # --- same name ---
    echo "[same name]"
    output=$(docker run --rm "$image" /chusername.sh oskkk oskkk 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "no changes needed" "prints no changes needed"

    # --- non-existent user ---
    echo "[non-existent user]"
    output=$(docker run --rm "$image" /chusername.sh ghost newuser 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "does not exist" "reports user not found"

    # --- target user already exists ---
    echo "[target user collision]"
    output=$(docker run --rm "$image" bash -c 'useradd -m taken && /chusername.sh oskkk taken' 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "already" "reports collision"

    # --- target group already exists ---
    echo "[target group collision]"
    output=$(docker run --rm "$image" bash -c 'groupadd takengrp && /chusername.sh oskkk takengrp' 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "already a group" "reports group collision"

    # --- non-root ---
    echo "[non-root]"
    output=$(docker run --rm --user 1000:1000 "$image" /chusername.sh oskkk newuser 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "root" "reports must be root"

    # --- happy path ---
    echo "[happy path]"
    output=$(docker run --rm "$image" bash -c '
        /chusername.sh oskkk newuser || exit 1

        id newuser > /dev/null 2>&1            || { echo "FAIL_USER"; exit 1; }
        id oskkk > /dev/null 2>&1              && { echo "FAIL_OLD_USER"; exit 1; }
        test -d /home/newuser                  || { echo "FAIL_HOME"; exit 1; }
        test ! -d /home/oskkk                  || { echo "FAIL_OLD_HOME"; exit 1; }
        grep -q "^newuser:" /etc/group         || { echo "FAIL_GROUP"; exit 1; }
        grep -q "^oskkk:" /etc/group           && { echo "FAIL_OLD_GROUP"; exit 1; }
        grep -q "^newuser:" /etc/subuid        || { echo "FAIL_SUBUID"; exit 1; }
        grep -q "^oskkk:" /etc/subuid          && { echo "FAIL_OLD_SUBUID"; exit 1; }
        grep -q "^newuser:" /etc/subgid        || { echo "FAIL_SUBGID"; exit 1; }
        grep -q "^oskkk:" /etc/subgid          && { echo "FAIL_OLD_SUBGID"; exit 1; }

        echo "ALL_CHECKS_PASSED"
    ' 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "username has been updated" "prints success"
    check_contains "$output" "ALL_CHECKS_PASSED" "user, group, home, subuid/subgid all correct"

    # --- rollback: usermod -l fails → group must be restored ---
    echo "[rollback: usermod -l failure]"
    output=$(docker run --rm "$image" bash -c "
        $(fake_usermod_script -l)

        /chusername.sh oskkk newuser 2>&1
        # expect failure

        id oskkk > /dev/null 2>&1            || { echo FAIL_USER_GONE; exit 1; }
        id newuser > /dev/null 2>&1          && { echo FAIL_NEW_USER; exit 1; }
        grep -q \"^oskkk:\" /etc/group       || { echo FAIL_GROUP_ROLLBACK; exit 1; }
        grep -q \"^newuser:\" /etc/group     && { echo FAIL_NEW_GROUP; exit 1; }
        test -d /home/oskkk                  || { echo FAIL_HOME; exit 1; }

        echo ROLLBACK_L_VERIFIED
    " 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0 (checks pass after rollback)"
    check_contains "$output" "rolled back" "reports rollback"
    check_contains "$output" "ROLLBACK_L_VERIFIED" "user, group, home intact after rollback"

    # --- rollback: usermod -d fails → user and group must be restored ---
    echo "[rollback: usermod -d failure]"
    output=$(docker run --rm "$image" bash -c "
        $(fake_usermod_script -d)

        /chusername.sh oskkk newuser 2>&1
        # expect failure

        id oskkk > /dev/null 2>&1            || { echo FAIL_USER_ROLLBACK; exit 1; }
        id newuser > /dev/null 2>&1          && { echo FAIL_NEW_USER; exit 1; }
        grep -q \"^oskkk:\" /etc/group       || { echo FAIL_GROUP_ROLLBACK; exit 1; }
        grep -q \"^newuser:\" /etc/group     && { echo FAIL_NEW_GROUP; exit 1; }
        test -d /home/oskkk                  || { echo FAIL_HOME; exit 1; }
        test ! -d /home/newuser              || { echo FAIL_NEW_HOME; exit 1; }

        echo ROLLBACK_D_VERIFIED
    " 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0 (checks pass after rollback)"
    check_contains "$output" "rolled back" "reports rollback"
    check_contains "$output" "ROLLBACK_D_VERIFIED" "user, group, home restored after rollback"

    docker rmi "$image" > /dev/null 2>&1
}

# --- Main ---

for distro in arch debian fedora alpine; do
    run_tests "$distro"
done

echo ""
if [[ $FAIL -eq 0 ]]; then
    green "=== All ${PASS} checks passed ==="
else
    red "=== ${PASS} passed, ${FAIL} failed ==="
    exit 1
fi
