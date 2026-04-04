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
    die "usage: $0 new_name old_name"
fi

new_name="$1"
old_name="$2"

if [[ "$new_name" == "$old_name" ]]; then
    echo "${PROG}: no changes needed"
    exit 0
fi

# Verify old user exists before touching anything
id "$old_name" &>/dev/null || die "user '$old_name' does not exist"

# Verify new name is not already taken
if getent group "$new_name" &>/dev/null; then
    die "there is already a group called '$new_name'"
fi
if id "$new_name" &>/dev/null; then
    die "there is already a user called '$new_name'"
fi

# --- Rename group
if ! groupmod -n "$new_name" "$old_name"; then
    die "failed to rename group"
fi

# --- Rename user login
if ! usermod -l "$new_name" "$old_name"; then
    groupmod -n "$old_name" "$new_name" 2>/dev/null
    die "failed to rename user (group has been rolled back)"
fi

# --- Move home directory
if ! usermod -d "/home/$new_name" -m "$new_name"; then
    usermod -l "$old_name" "$new_name" 2>/dev/null
    groupmod -n "$old_name" "$new_name" 2>/dev/null
    die "failed to move home directory (user and group have been rolled back)"
fi

# --- Update subuid/subgid for rootless containers
files_to_edit=("/etc/subuid" "/etc/subgid")
for file in "${files_to_edit[@]}"; do
    if [[ -f "$file" ]] && grep -q "^${old_name}:" "$file"; then
        sed -i "s/^${old_name}:/${new_name}:/" "$file"
    fi
done

echo "${PROG}: username has been updated"

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
