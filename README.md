# chusername

## Warning
From [Users_and_groups#Change_a_user's_login_name_or_home_directory](https://wiki.archlinux.org/title/Users_and_groups#Change_a_user's_login_name_or_home_directory) 

> Also keep in mind the following notes:
> - If you are using sudo make sure you update your /etc/sudoers to reflect the new username(s) (via the visudo command as root).
> - Personal crontabs need to be adjusted by renaming the user's file in /var/spool/cron from the old to the new name, and then opening crontab -e to change any relevant paths and have it adjust the file permissions accordingly.
> - Wine's personal directories/files' contents in ~/.wine/drive_c/users, ~/.local/share/applications/wine/Programs and possibly more need to be manually renamed/edited.
> - Certain Thunderbird addons, like Enigmail, may need to be reinstalled.
> - Anything on your system (desktop shortcuts, shell scripts, etc.) that uses an absolute path to your home dir (i.e. /home/oldname) will need to be changed to reflect your new name. To avoid these problems in shell scripts, simply use the ~ or $HOME variables for home directories.
> - Also do not forget to edit accordingly the configuration files in /etc/ that relies on your absolute path (e.g. Samba, CUPS, so on). A nice way to learn what files you need to update involves using the grep command this way: grep -r old_user *

- Occurrences of old_user in backup files (files with trailing hyphen), such as /etc/group-, /etc/gshadow-, etc., can be safely ignored.

## Usage

- Switch to the root user:
```sh
$ su -
```
- Usage example:
```sh
# ./chusername.sh new_name old_name
```
- Read the warning.
