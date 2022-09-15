#!/bin/bash

# Mikael Haglund - mikael@netcamp.se
# TNNC Netcamp

FILE_FOLDER="/tmp/foobar"
CHECKSUM_FOLDER="/tmp/checksum/"
DSTFOLDER="/tmp/foobar2"



cd $FILE_FOLDER
for file_path in $(find . -type f -printf '%P\n' 2>/dev/null); do
    CHECKSUM_FILE="$CHECKSUM_FOLDER/$file_path"
    if [ -f "$CHECKSUM_FILE.sha256" ]; then
	checksum=$(cat "$CHECKSUM_FILE.sha256")
        checksum_tool="sha256sum"
    elif [ -f "$CHECKSUM_FILE.sha1" ]; then
	checksum=$(cat "$CHECKSUM_FILE.sha1")
        checksum_tool="sha1sum"
    elif [ -f "$CHECKSUM_FILE.md5" ]; then
	checksum=$(cat "$CHECKSUM_FILE.md5")
        checksum_tool="md5sum"
    else
        continue
    fi

    file_checksum=$("$checksum_tool" "$file_path" | awk '{print $1}')
    if [[ "$file_checksum" == "$checksum" ]]; then
       mkdir -p $(dirname ${DSTFOLDER}/${file_path} ) 
       rsync -ra --checksum "$file_path" "$(dirname ${DSTFOLDER}/${file_path} )"
       echo "Checksum match"
    else
       echo "Checksum did not match"

    fi
   
done

