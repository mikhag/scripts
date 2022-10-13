
#SOURCE_PATH="/srv/protectera/syncfolder/ubuntu"
#SOURCE_PATH="/tmp"
SOURCE_PATH="/var/spool/apt-mirror/mirror"
TMP_PATH="/srv/protectera/syncfolder/ubuntu"
VERIFIED_PATH="/srv/protectera/syncfolder/ubuntu_verified"

APT_GPG_FOLDER="/etc/apt/trusted.gpg.d/"

OUTPUT_LOGLEVEL=7
SYSLOG_LOGLEVEL=7
SYSLOG_LOGFACILITY=local3


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
#    if [[  "$SYSLOG_LOGLEVEL" -ge "$msg_loglevel"   ]]; then
        #logger -id verifyWsus -p "${SYSLOG_LOGFACILITY}.${msg_loglevel}" "$msg"
#    fi
}

# - verify_gpg_signature -
# Verifies the GPG-signature of the "Release" file for repo
#   - $1 Reopository (eg. focal, focal-upates)
verify_gpg_signature(){
    #
    #Verify Release
    file=$1
    # Collect all gpg-keyrings
    gpg --keyring /etc/apt/trusted.gpg --export  > /tmp/.repo.gpg.$$
    find /etc/apt/trusted.gpg.d/ -name "*.gpg" -exec gpg --keyring {} --export  > /tmp/.repo.gpg.$$ \;
    
    #Check if gpg file exist
    if [ -e "$file.gpg" ]; then
       gpgv --keyring /tmp/.repo.gpg.$$ $file.gpg $file 2>&1 |\
          grep "gpgv: Good signature from" > /dev/null 2>&1
    else
       gpgv --keyring /tmp/.repo.gpg.$$ $file 2>&1 |\
            grep "gpgv: Good signature from" > /dev/null 2>&1
    fi

    #Depending on gpg exitcode
    if [[ "$?" == 0 ]]; then
        log 7 "DEBUG: Signature Validated for ${repo}"
        ec=0
    else
        log 7 "DEBUG: Signature not validated"
        ec=1
    fi

    #Remove gpg-collection
    rm /tmp/.repo.gpg.$$

    #Returncode
    return $ec
}


# checksum_package
#Verify checksum between package on filesystem and repo
#   - $1  - Filename from "Package" file
#   - $2  - SHA256 checksum from releasefile
checksum_package(){
    repo_filename=$1
    repo_sha256=$2
    repo_filepath="${_LOCAL_REPOPATH}${repo_filename}"
    if [[ -e "$repo_filepath" ]]; then

        repo_filepath="${poolfolder}/${repo_filename}"

	#SHA1 and filename
        filesum=$(sha256sum "$repo_filepath")
        file_sha256=$(IFS='\t' echo $filesum | awk  '{print $1}' )
        file_filename=$(basename "$repo_filepath")

        #If sha256 same, and not empty
        if [[ "$repo_sha256" == "$file_sha256" ]] && [ -n "$repo_sha256" ]; then
            log 7 "DEBUG: Correct hash for '${repo_filepath}'  [$repo_sha256=$file_sha256]"
            return 0
        fi
        log 7 "DEBUG: Wrong hash for '${repo_filepath}'  [$repo_sha256=$file_sha256]"
        return 1
    else
        log 7 "DEBUG: No file found '${repo_filepath}'"
        return 10
    fi
}


getrepo_pkg_hashsums(){
    pkgfile=$1
    dirname=$2
    #Get Pagackge.gz from TMP_SOURCE, which has been validated
    package_file="${TMP_PATH}/${pkgfile}"

    #Check where pool folder is located (folder with all packages)
    if [ -e "$dirname/../../pool" ]; then
        poolfolder=$(realpath "$dirname/../../")
    elif [ -e "$dirname/pool" ]; then
        poolfolder="$dirname"
    else
        log 3 "Unable to locate pool catalog for ${package_file}"
	return 2
    fi

    #Count number of packages in file
    pkg_count=$(zcat "${package_file}" | grep Filename | wc -l)
    log 6 "INFO: Retriving checksums for ${pkg_count} packages from: '${package_file}'"

    #Counter
    n=0

    cd $poolfolder

    #While read Packages file and for each row (indata at the end of loop)
    while read -r  line
    do
       #If line is empty (new package)
       if [[ $line == "" ]]; then
           # Add 1 to counter and print
           n=$(echo $n+1 | bc)
           log 7 "DEBUG: Loading checksum: ${n}/${pkg_count} - ${filename}"
           #if filename and SHA is set, check corresponding file
           if [ -n "$filename"   ] && [ -n "$sha256" ]; then
                checksum_package "${filename}" "$sha256"
                if [[ "$?" == "0" ]]; then
                        copy_file "${filename}" 1
                        log 6 "INFO: Checksum correct for: ${filename}"
                elif [[ "$?" == "10" ]]; then
                        log 4 "WARNING: File missing: ${filename}"
                else
                        log 3 "ERROR: Checksum check FAILED for: ${filename}"
                fi
           else
               log 3 "ERROR: Info about package not complete NAME:${filename}  SHA256:${sha256}"
           fi
           #Unset filename and SHA since new package
           unset filename
           unset sha256

       else
          # Extract Line-title and Line-value from row
          line_title=$(echo $line | awk -F ":" '{print $1}' | sed -e 's/^[[:space:]]*//')
          line_value=$(echo $line | awk -F ":" '{print $2}' | sed -e 's/^[[:space:]]*//')

          #Get filename
          if [[ $line_title == "Filename" ]]; then
              filename=$line_value

          #Get SHA256
          elif [[ $line_title == "SHA256" ]]; then
              sha256=$line_value
          fi
       fi
    done < <(zcat "${package_file}" | grep -E "SHA256|Filename|^$")
    cd $SOURCE_PATH
}

#Full filepath
copy_file(){
    mkdir -p ${TMP_PATH}

     #Use LS to get "clean paths"
     file=$(realpath $1)
     source_repo=$(ls -1 -d ${SOURCE_PATH})
     dest_repo=$(ls -1 -d ${TMP_PATH})
     newfile=$(echo $file | sed -E "s%${source_repo}%${dest_repo}%")
     echo "copying ${file} -> ${newfile}"
     mkdir -p $(dirname $newfile)
     if [[ "$2" != "1" ]]; then
       rsync -ra "$file" "$newfile"
     fi

}


for inrelease in $(find "$SOURCE_PATH" -name "InRelease" 2> /dev/null); do
   dirname=$(dirname $inrelease)
   cd "$dirname"
 
   # 
   #Verify InRelease-file 
   verify_gpg=$(verify_gpg_signature $inrelease)
   if [[ $? != 0 ]] ; then
        log 3 "ERROR: Signature not correct $inrelease, skipping repo"
        continue
   fi
   log 6 "GPG OK - $inrelease"
   copy_file $inrelease

   #
   #Verify Release-file 
   verify_gpg=$(verify_gpg_signature "$dirname/Release")
   if [[ $? != 0 ]] ; then
        log 3 "ERROR: Signature not correct $dirname/Release, skipping repo"
        continue
   fi
   log 6 "GPG OK - $dirname/Release, $file/Release.gpg"
   copy_file "$dirname/Release"
   copy_file "$dirname/Release.gpg"

   #
   #Check files in dist-folder against Release
   allFiles=$(cat Release | grep "^ " | awk '{print $3}' | sort | uniq)
   for file in $allFiles; do 
      if [ ! -e "$file" ]; then
         log 6 "File '$dirname/$file' does not exist, continueing"
         continue
      fi
      #Get filehash
      fhash=$(sha256sum  "$dirname/$file" | awk '{print $1}') 
      #Compare that filehash match with filename in Release-File
      grep "\s$fhash\s.*\s$file\$" ./Release
      if [[ $? != 0 ]] ; then
        log 3 "ERROR: File signature not correct, skipping ($file)"
        continue
      fi
      copy_file "$dirname/$file"
   done
  
   cd $SOURCE_PATH

   for pkgfile in $(find . -name Packages.gz  | sed -e "s%./%%"); do
     getrepo_pkg_hashsums $pkgfile $dirname
   done


   cd $SOURCE_PATH

done
