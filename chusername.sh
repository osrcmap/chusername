#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "chusername: the number of arguments provided is incorrect" >&2
    exit 1
fi

new_name="$1"
old_name="$2"

if [[ "$new_name" == "$old_name" ]]; then
    echo "chusername: no changes needed"
    exit 0
fi

getent group $new_name 
if [[ $? -eq 0 ]]; then
    echo "chusername: there is already a group called $new_name" >&2
    exit 1
fi

groupmod -n $new_name $old_name
if [[ $? -ne 0 ]]; then
    exit 1
fi
# usermod verifies that the user $old_name exists, user $new_name does not already exist, both usernames are valid
usermod -l $new_name $old_name
if [[ $? -ne 0 ]]; then
    exit 1
fi
usermod -d /home/$new_name -m $new_name
if [[ $? -ne 0 ]]; then
    exit 1
fi

# usermod and groupmod automatically manage changes to some /etc/ files
#for file in $(grep -r -m 1 $old_name /etc/ | cut -d ":" -f 1); do
#    sed -i "s/$old_name/$new_name/g" $file
#done

files_to_edit=("/etc/subuid" "/etc/subgid")
for file in ${files_to_edit[@]}; do
    if grep -q "^${old_name}:" $file; then
        sed -i "s/^${old_name}:/${new_name}:/" $file
    fi
done

# ?
#grpck
#pwck

echo "chusername: username has been updated"

echo -e "\nNote:"
echo "Quoting https://wiki.archlinux.org/title/Users_and_groups#Change_a_user's_login_name_or_home_directory."
echo "  - If you are using sudo make sure you update your /etc/sudoers to reflect the new username(s) (via the visudo command as root)."
echo "  - Personal crontabs need to be adjusted by renaming the user's file in /var/spool/cron from the old to the new name, and then opening crontab -e to change any relevant paths and have it adjust the file permissions accordingly."
echo "  - Wine's personal directories/files' contents in ~/.wine/drive_c/users, ~/.local/share/applications/wine/Programs and possibly more need to be manually renamed/edited."
echo "  - Certain Thunderbird addons, like Enigmail, may need to be reinstalled."
echo "  - Anything on your system (desktop shortcuts, shell scripts, etc.) that uses an absolute path to your home dir (i.e. /home/oldname) will need to be changed to reflect your new name. To avoid these problems in shell scripts, simply use the ~ or \$HOME variables for home directories."
echo "  - Also do not forget to edit accordingly the configuration files in /etc/ that relies on your absolute path (e.g. Samba, CUPS, so on). A nice way to learn what files you need to update involves using the grep command this way: grep -r old_user *"
echo "  - Occurrences of old_user in backup files (files with trailing hyphen), such as /etc/group-, /etc/gshadow-, etc., can be safely ignored."
# echo "  - To run rootless containers, manually edit /etc/subgid and /etc/subuid to match the new_name. Otherwise, occurrences of "old_name" can be safely ignored."
