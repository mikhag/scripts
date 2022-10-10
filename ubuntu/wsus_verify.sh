#!/bin/bash

# Mikael Haglund - mikael@netcamp.se
# TNNC-Netcamp
#
# Values below are std values and can be override by
# editing wsus_verify.config in the config-path (./etc/wsus_verify/)

#PATH where WSUS is exported to
WSUS_PATH=/srv/protectera/Export/WSUS/
#PATH where verified files should land
WSUS_VERIFIED_PATH=/srv/protectera/Export/WSUS_verified2/
#The TMP-path is used during verification, before replacing verified folder
WSUS_TMP_PATH=/srv/protectera/Export/WSUS_verified_tmp/
WSUS_USE_TMP_PATH=1

#Folder with config-files
CONFIG_PATH=/opt/protectera/etc/wsus_verify/

#File containing root-certificates to check file signatures against
CAFILE=${CONFIG_PATH}/cafile.crt

#File that contains exceptions for verification
VERIFICATION_EXCEPTIONS=${CONFIG_PATH}/file_verify_exeptions

#File where script append files that fail verification
CERT_VERIFICATION_FAILED=${CONFIG_PATH}/file_verify_fails

#Max size of txt file before its removed, 2MB
TXT_MAX_SIZE_BYTES=$(echo 2*1024*1024 | bc)

#Which log level to send to screen, and/or to syslog
#1=alert,2=critical,3=error,
#4=warning,5=notice,6=info,7=debug
OUTPUT_LOGLEVEL=5
SYSLOG_LOGLEVEL=5
SYSLOG_LOGFACILITY=local3

# Get user config values
source ${CONFIG_PATH}/wsus_verify.config

#
#
#


addFileToFailed(){
    log 6 "INFO:Adding file to list of FAILED files, if not already there"
    if ! grep -E "^${1}\$" $CERT_VERIFICATION_FAILED > /dev/null 2>&1; then
        log 7 "DEBUG:Not there! Adding..."
        echo "${1}"      >> $CERT_VERIFICATION_FAILED
    fi
}

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

# Verify file checksum against name
# EXE and CAB Files are named according to SHA1-checksum
# Currently only supports CAB and EXE files
verify_checksum(){
    # $1 - Filepath including name to check 
    filename=$(basename "$1")
    log 7 "DEBUG:Verifing checksum of ${1} filename: ${filename}"

    #Calculate the SHA1 checksum of file
    calcsum=$(sha1sum "$1" | awk '{print  $1}')

    #Extract hash from filename by removing the extension (exe or cab)
    filesum=$(echo "$filename" | sed -E "s%([A-Za-z0-9]+)(\.exe|\.cab)%\1%" )
    
    
    log 7 "DEBUG:Checksum from filename: ${filesum} calculated: ${calcsum}"
    # Compare the two hashes, make calcsum uppercase, if correct return 0
    if [[ "${calcsum^^}" == "$filesum"  ]]; then
        log 7 "DEBUG:Checksums: Match"
        return 0
    fi
    log 7 "DEBUG:Checksums: Not-Match"
    return 1
}
    
start_time=$(date +"%s")
log 5 "WSUS verification started at $(date)"

# Prepare destination_folder

#
#Check if TMP path should be used, otherwise work directly with verified
CP_PATH=$WSUS_VERIFIED_PATH
if [[ "WSUS_USE_TMP_PATH" == "1" ]]; then
    CP_PATH=$WSUS_TMP_PATH
    log 6 "INFO: Using TMP-path ${TMP_PATH}"
fi

#Remove the destination folder
rm -rf "$CP_PATH"



#
# Loop through all files in WSUS_PATH
#

IFS="
"
for file in $(find ${WSUS_PATH} -type f ); do
     # Get filename (without path) and file exception for each file
     fileext=$(echo $file | grep -oE "\..+")
     filename=$(basename "$file")
     log 7 "DEBUG:Start the verification of ${file} - name: ${filename} ext: ${fileext}"


     #Check file against file with known verification exceptions
     if grep -E "^${filename}\$|^${filename}:(accept|ignore|checksum)\$" "$VERIFICATION_EXCEPTIONS" > /dev/null 2>&1; then
	 #If exeption exist with ignore parameter, just ignore the file
         if grep -E "^${filename}:(ignore)\$" "$VERIFICATION_EXCEPTIONS" > /dev/null 2>&1; then
             log 6 "INFO: $file - $filename exist as exception, the file will be ignored"
             continue
	 #if exeption has accept parameter
         elif grep -E "^${filename}:(accept)\$" "$VERIFICATION_EXCEPTIONS" > /dev/null 2>&1; then
             log 6 "INFO: $file - $filename exist as exception, the file will not be scanned"
	 else
             log 6 "INFO: $file - $filename exist as exception, but with checksum control"
             if ! verify_checksum "$file"; then
                 log 1 "ERROR:Checksum of file $file, not correct"
                 continue
             fi
         fi
     #For exe and cab files files, check the file signature against cert-chain 
     elif [[ $fileext == ".cab" ]] || [[ $fileext == ".exe" ]]; then
	# EXE and CAB is named according to its SHA! checksum,
	# If not corresponding
        if ! verify_checksum "$file"; then
            log 3 "ERROR:Checksum of file $file, not correct"
	    continue
        fi

        log 7 "DEBUG: $filename identified as $fileext"
        #First we extract the EXE files cert-signature, and verify that the chain is complete and working
        #	
        #Extract signature from file
        #osslsigncode verify  -in ${file} -out "/tmp/wsus.verify.$filename.sig" > /dev/null 2>&1
	./osslsigncode verify -TSA-CAfile "$CAFILE" -CAfile "$CAFILE" "$file" > /dev/null
    	
        #If certificate check failed
        if [[ "$?" != "0"  ]]; then
            log 3 "ERROR: $filename did not comply with any known certchains"
            #Add file to VERIFICATION_FAILED file
            addFileToFailed "$filename"
       	    #Continue with next update
            continue
       fi

    # If TXT file, just check file-size that its not bigger than what is reasonable, 
    # thats all we can do for now
    elif [[ "$fileext" == ".txt" ]];  then
            log 7 "DEBUG: $filename identified as TXT"
	    filesize=$(stat -c%s $file)
	    log 7 "DEBUG: checking $filename size ($filesize) Max allowed($TXT_MAX_SIZE_BYTES)"
	    if [[ "$filesize" -gt "$TXT_MAX_SIZE_BYTES" ]]; then
	        log 3 "ERROR: $filename ($filesize) is bigger than max allowed ($TXT_MAX_SIZE_BYTES)"
		#Add file to list of failed files, and continue with next file
                addFileToFailed "$filename"
		continue
	    fi

    # For files not matching above, probably a fileextension not supported
    else
        log 3 "ERROR: $filename - Verification of fileext $fileext not supported, you could add this file as exception in: $VERIFICATION_EXCEPTIONS"
        addFileToFailed "$filename"
	continue
    fi
    #
    #   -- COPY --
    #
    #If reach here, the checks above was correct and we can start copy!


    #Take current file, replace WSUS_PATH with destination path
    newfile=$(echo $file | sed -E "s%${WSUS_PATH}%${CP_PATH}%")
    
    #Create the destination-path and start copy 
    log 6 "INFO: Copying ${file} -> ${newfile}"
    mkdir -p $(dirname "$newfile")
    rsync -ra "${file}" "${newfile}"

done


#Syncing TMP folder with destinationfolder if required
if [[ "WSUS_USE_TMP_PATH" == "1" ]] &&\
   [ -n $CP_PATH ] && [ -n $WSUS_VERIFIED_PATH ]; then
    rsync_out=$(rsync -raP --delete --checksum "$CP_PATH/*" "$WSUS_VERIFIED_PATH/")
    log 7 "DEBUG: ${rsync_out}"
    rm -rf $CP_PATH
fi
done_time=$(date +"%s")
log 5 "WSUS verification completed at $(date) - Execution-time $(echo "$done_time"-"$start_time" | bc) sec"

