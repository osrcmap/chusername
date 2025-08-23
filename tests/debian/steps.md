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

# Storing files to edit
files_to_edit=( $(grep -r -m 1 <old_name> /etc/ | cut -d ":" -f 1) )
echo ${files_to_edit[@]}
# Iterate over the files_to_edit and edit them
for file in "${files_to_edit[@]}"; do
    sed -i 's/<old_name>/<new_name>/g' $file
done

# Or shorter
for file in $(grep -r -m 1 <old_name> /etc/ | cut -d ":" -f 1); do
    sed -i 's/<old_name>/<new_name>/g' $file
done
