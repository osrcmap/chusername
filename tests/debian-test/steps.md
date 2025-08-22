# Steps to change username
## Run as root
usermod -l <new_name> <old_name> // Change username
groupmod -n <new_name> <old_name> // Change associated group for the user
usermod -d /home/<new_name> -m <new_name> // Change home directory (this replace the old home folder with the new one (IDK if it's because that old folder have no content))

The occurrences of <old_name> were replaced with <new_name> automatically

Only the following commands return <old_name> occurrences
grep -r <old_name> /etc
grep -r <old_name> /proc
grep -r <old_name> /sys
