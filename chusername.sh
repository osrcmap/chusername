#!bin/bash

if [[ $# -ne 2 ]]; then
    echo "chusername: the number of arguments provided is incorrect" >$2
    exit 1
fi

new_name="$1"
old_name="$2"

if [[ "$new_name" == "$old_name" ]]; then
    echo "chusername: no changes needed"
    exit 0
fi

for group_name in $(cat /etc/group | cut -d ":" -f 1); do
    if [[ $new_name == $group_name ]]; then
        echo "chusername: there is already a group called $new_name"
        exit 1
    fi
done

# usermod verifies that the user $old_name exists, user $new_name does not already exist, both usernames are valid
usermod -l $new_name $old_name
if [[ $? -ne 0 ]]; then
    exit 1
fi
groupmod -n $new_name $old_name
usermod -d /home/$new_name -m $new_name

for file in $(grep -r -m 1 $old_name /etc/ | cut -d ":" -f); do
    sed -i 's/$old_name/new_name/g' $file
done
# ?
#grpck
#pwck
