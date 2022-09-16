#!/bin/bash

# Mikael Haglund - mikael@netcamp.se
# TNNC Netcamp

FILE_FOLDER="/tmp/foobar"
CHECKSUM_FOLDER="/tmp/checksum/"
DSTFOLDER="/tmp/foobar2"

log(){
    level=$1
    msg=$2
    echo $2
}


cd $FILE_FOLDER
for file_path in $(find . -type f -printf '%P\n' 2>/dev/null); do
    log 6 "Processing file: $file_path"
    CHECKSUM_FILE="$CHECKSUM_FOLDER/$file_path"
    if [ -f "$CHECKSUM_FILE.sha256" ]; then
        log 6 "Found SHA256 file: ${CHECKSUM_FILE}.sha256"
	checksum=$(cat "$CHECKSUM_FILE.sha256")
        checksum_tool="sha256sum"
    elif [ -f "$CHECKSUM_FILE.sha1" ]; then
        log 6 "Found SHA1 file: ${CHECKSUM_FILE}.sha1"
	checksum=$(cat "$CHECKSUM_FILE.sha1")
        checksum_tool="sha1sum"
    elif [ -f "$CHECKSUM_FILE.md5" ]; then
        log 6 "Found MD5 file: $CHECKSUM_FILE.md5"
	checksum=$(cat "${CHECKSUM_FILE}.md5")
        checksum_tool="md5sum"
    else
        continue
    fi

    file_checksum=$("$checksum_tool" "$file_path" | awk '{print $1}')
    log 6 "Calculated checksum: ${file_checksum}   Checksum from file: ${checksum}"
    if [[ "$file_checksum" == "$checksum" ]]; then
       log 6 "Match, copying $file_path -> ${DSTFOLDER}/${file_path}"
       mkdir -p $(dirname ${DSTFOLDER}/${file_path} ) 
       rsync -ra --checksum "$file_path" "${DSTFOLDER}/${file_path}"
    else
       log 3 "ERROR: Checksum for file did not match! ${file_path} - Calculated checksum: ${file_checksum}   Checksum from file: ${checksum}"
    fi
    log 6 "--------------------------------------"

done

