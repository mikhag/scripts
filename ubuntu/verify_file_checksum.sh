#!/bin/bash

# Mikael Haglund - mikael@netcamp.se
# TNNC Netcamp

FILE_FOLDER="/tmp/foobar"
CHECKSUM_FOLDER="/tmp/checksum/"
DSTFOLDER="/tmp/foobar2"
#
#Which log level to send to screen, and/or to syslog
#1=alert,2=critical,3=error,
#4=warning,5=notice,6=info,7=debug
OUTPUT_LOGLEVEL=5
SYSLOG_LOGLEVEL=5
SYSLOG_LOGFACILITY=local3
#


# - log -
# Receives msg-loglevel and log-message, and print if LOGLEVEL is greater than msg-loglevel
#   - $1  - Message Log Level
#   - $2  - Message
log(){

    msg_loglevel=$1
    msg=$2

    #Check if message should be printed on screen
    if [[  "$OUTPUT_LOGLEVEL" -ge "$msg_loglevel"   ]]; then
        echo $msg
    fi
    #Check if message should be sent to syslog, then do it
    if [[  "$SYSLOG_LOGLEVEL" -ge "$msg_loglevel"   ]]; then
        logger -id verifyWsus -p "${SYSLOG_LOGFACILITY}.${msg_loglevel}" "$msg"
    fi
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

