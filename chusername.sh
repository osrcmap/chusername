#!/bin/bash

set -u

readonly PROG="chusername"

die() {
    echo "${PROG}: $1" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    die "must be run as root"
fi

if [[ $# -ne 2 ]]; then
    die "usage: $0 old_name new_name"
fi

old_name="$1"
new_name="$2"

if [[ "$new_name" == "$old_name" ]]; then
    echo "${PROG}: no changes needed"
    exit 0
fi

# A leading '-' would be parsed as an option by id/groupmod/usermod
if [[ "$old_name" == -* || "$new_name" == -* ]]; then
    die "names must not start with '-'"
fi

# Verify old user exists before touching anything
id "$old_name" &>/dev/null || die "user '$old_name' does not exist"

# Verify new name is not already taken
if id "$new_name" &>/dev/null; then
    die "there is already a user called '$new_name'"
fi

# Only rename the primary group if it is named after the user
rename_group=0
if [[ "$(id -gn "$old_name")" == "$old_name" ]]; then
    rename_group=1
    if getent group "$new_name" >/dev/null; then
        die "there is already a group called '$new_name'"
    fi
fi

# Only move the home directory if it is named after the user, keeping its parent
old_home="$(getent passwd "$old_name" | cut -d: -f6)"
new_home=""
if [[ "${old_home##*/}" == "$old_name" ]]; then
    new_home="${old_home%/*}/$new_name"
fi

group_renamed=0
user_renamed=0

rollback() {
    local ok=1
    if (( user_renamed )); then
        usermod -l "$old_name" "$new_name" || ok=0
    fi
    if (( group_renamed )); then
        groupmod -n "$old_name" "$new_name" || ok=0
    fi
    if (( ok )); then
        die "$1 (changes have been rolled back)"
    fi
    die "$1 (ROLLBACK FAILED: check user and group '$new_name' manually)"
}

# Don't let Ctrl-C or a dropped session leave the rename half done
trap '' INT TERM HUP

# --- Rename group
if (( rename_group )); then
    groupmod -n "$new_name" "$old_name" || die "failed to rename group"
    group_renamed=1
fi

# --- Rename user login
usermod -l "$new_name" "$old_name" || rollback "failed to rename user"
user_renamed=1

# --- Move home directory
if [[ -n "$new_home" ]]; then
    usermod -d "$new_home" -m "$new_name" || rollback "failed to move home directory"
fi

status=0

# --- Update subuid/subgid for rootless containers
# Names may contain '.', so escape them for sed
old_re="$(printf '%s' "$old_name" | sed 's/[][\.*^$/]/\\&/g')"
new_re="$(printf '%s' "$new_name" | sed 's/[\&/]/\\&/g')"
for file in /etc/subuid /etc/subgid; do
    if [[ -f "$file" ]] && ! sed -i "s/^${old_re}:/${new_re}:/" "$file"; then
        echo "${PROG}: failed to update $file, rename '$old_name' entries to '$new_name' manually" >&2
        status=1
    fi
done

# --- Rename per-user crontab and systemd linger files
for dir in /var/spool/cron /var/spool/cron/crontabs /etc/crontabs /var/lib/systemd/linger; do
    if [[ -f "$dir/$old_name" && ! -e "$dir/$new_name" ]]; then
        mv "$dir/$old_name" "$dir/$new_name" || status=1
    fi
done

echo "${PROG}: username has been updated"

if sudoers="$(grep -rlwF -- "$old_name" /etc/sudoers /etc/sudoers.d 2>/dev/null)"; then
    echo "${PROG}: '$old_name' is still referenced in (edit with visudo):"
    echo "$sudoers"
fi

cat <<'EOF'

Note:
Quoting https://wiki.archlinux.org/title/Users_and_groups#Change_a_user's_login_name_or_home_directory.
  - If you are using sudo make sure you update your /etc/sudoers to reflect the new username(s) (via the visudo command as root).
  - Personal crontabs need to be adjusted by renaming the user's file in /var/spool/cron from the old to the new name, and then opening crontab -e to change any relevant paths and have it adjust the file permissions accordingly.
  - Wine's personal directories/files' contents in ~/.wine/drive_c/users, ~/.local/share/applications/wine/Programs and possibly more need to be manually renamed/edited.
  - Certain Thunderbird addons, like Enigmail, may need to be reinstalled.
  - Anything on your system (desktop shortcuts, shell scripts, etc.) that uses an absolute path to your home dir (i.e. /home/oldname) will need to be changed to reflect your new name. To avoid these problems in shell scripts, simply use the ~ or $HOME variables for home directories.
  - Also do not forget to edit accordingly the configuration files in /etc/ that relies on your absolute path (e.g. Samba, CUPS, so on). A nice way to learn what files you need to update involves using the grep command this way: grep -r old_user *
  - Occurrences of old_user in backup files (files with trailing hyphen), such as /etc/group-, /etc/gshadow-, etc., can be safely ignored.
EOF

exit "$status"
