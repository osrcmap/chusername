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

# Create a fake usermod that fails when its arguments match a sh case pattern
# (matched against " $* ") and passes everything else to the real binary.
#   $1 — pattern, e.g. '*" -l "*' (no single quotes, % or backslashes)
fake_usermod_script() {
    local pattern="$1"
    cat <<WRAPPER
        umod=\$(command -v usermod)
        mv "\$umod" "\${umod}.real"
        printf '#!/bin/sh\ncase " \$* " in $pattern) exit 1;; esac\nexec "%s.real" "\$@"\n' "\$umod" > "\$umod"
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
        mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/oskkk
        /chusername.sh oskkk newuser || exit 1

        test -f /var/lib/systemd/linger/newuser || { echo "FAIL_LINGER"; exit 1; }
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
        $(fake_usermod_script '*" -l "*')

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
        $(fake_usermod_script '*" -d "*')

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

    # --- rollback itself fails → must not claim success ---
    echo "[rollback failure reported]"
    output=$(docker run --rm "$image" bash -c "
        $(fake_usermod_script '*" -d "*|*" -l oskkk "*')
        /chusername.sh oskkk newuser
    " 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "ROLLBACK FAILED" "reports failed rollback"

    # --- option-like name ---
    echo "[option-like name]"
    output=$(docker run --rm "$image" /chusername.sh --help newuser 2>&1)
    rc=$?
    check_exit "$rc" 1 "exits 1"
    check_contains "$output" "must not start with" "rejects leading '-'"

    # --- dotted name must not touch a look-alike user's subuid/subgid ---
    echo "[dotted name]"
    output=$(docker run --rm "$image" bash -c '
        useradd -m johnxdoe && useradd -m john.doe || exit 1
        for f in /etc/subuid /etc/subgid; do
            echo "johnxdoe:200000:65536" >> $f
            echo "john.doe:300000:65536" >> $f
        done
        /chusername.sh john.doe jd || exit 1

        for f in /etc/subuid /etc/subgid; do
            grep -q "^johnxdoe:200000:" $f     || { echo "FAIL_LOOKALIKE $f"; exit 1; }
            grep -q "^jd:300000:" $f           || { echo "FAIL_RENAMED $f"; exit 1; }
            grep -q "^jd:200000:" $f           && { echo "FAIL_WRONG_ENTRY $f"; exit 1; }
        done
        test -d /home/jd                       || { echo "FAIL_HOME"; exit 1; }

        echo "DOTTED_OK"
    ' 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "DOTTED_OK" "only the renamed user's entries change"

    # --- primary group not named after the user ---
    echo "[shared primary group]"
    output=$(docker run --rm "$image" bash -c '
        grep -q "^users:" /etc/group || groupadd users
        groupadd bob && useradd -m -g users bob || exit 1
        /chusername.sh bob bob2 || exit 1

        [ "$(id -gn bob2)" = users ]           || { echo "FAIL_PRIMARY_GROUP"; exit 1; }
        grep -q "^bob:" /etc/group             || { echo "FAIL_UNRELATED_GROUP_RENAMED"; exit 1; }
        grep -q "^users:" /etc/group           || { echo "FAIL_USERS_GROUP"; exit 1; }
        test -d /home/bob2                     || { echo "FAIL_HOME"; exit 1; }

        echo "GROUP_OK"
    ' 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "GROUP_OK" "user renamed, groups untouched"

    # --- home outside /home stays in its parent dir ---
    echo "[home outside /home]"
    output=$(docker run --rm "$image" bash -c '
        mkdir -p /srv && useradd -m -d /srv/carol carol || exit 1
        /chusername.sh carol carol2 || exit 1

        test -d /srv/carol2                    || { echo "FAIL_HOME"; exit 1; }
        test ! -e /home/carol2                 || { echo "FAIL_MOVED_TO_HOME"; exit 1; }
        getent passwd carol2 | grep -q ":/srv/carol2:" || { echo "FAIL_PASSWD"; exit 1; }

        echo "HOME_OK"
    ' 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "HOME_OK" "home moved within /srv"

    # --- sudoers reference is reported ---
    echo "[sudoers hint]"
    output=$(docker run --rm "$image" bash -c '
        mkdir -p /etc/sudoers.d && echo "oskkk ALL=(ALL) ALL" > /etc/sudoers.d/oskkk
        /chusername.sh oskkk newuser
    ' 2>&1)
    rc=$?
    check_exit "$rc" 0 "exits 0"
    check_contains "$output" "/etc/sudoers.d/oskkk" "lists sudoers file"

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
