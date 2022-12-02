#!/bin/bash

# Mikael Haglund - mikael@netcamp.se
# TNNC Netcamp
# This script verifies the authenticity of files in a Ubunutu repository
#

#Mirror Server URI
MIRROR_SERVER="archive.ubuntu.com"
#Which repos to check
REPOS+=( 
"focal:main,universe", 
"focal-security:main,restricted,universe" 
"focal-updates:main,restricted,universe" 
)

#Path to the repo
LOCAL_REPOPATH="/srv/protectera/syncfolder/ubuntu"
#LOCAL_REPOPATH="/srv/protectera/syncfolder/ubuntu/mirror/archive.ubuntu.com/ubuntu/"
VERIFIED_REPOPATH="/srv/protectera/syncfolder/ubuntu_verified"
#
APT_KEYRING="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
#

#Which log level to send to screen, and/or to syslog
#1=alert,2=critical,3=error,
#4=warning,5=notice,6=info,7=debug
OUTPUT_LOGLEVEL=5
SYSLOG_LOGLEVEL=5
SYSLOG_LOGFACILITY=local3





# UBUNTU repo is built up by folder structure, some intresting paths
#
# /dists/$repo/Release - Signed files with checksums for files in /dists/$repo folder
# /dists/$repo/$section/binary-amd64/Packages.xz - File containing checksums for deb in /pool-folder
# /pool - folderstructure where all deb files is stored
#

# checksum_package
#Verify checksum between package on filesystem and repo
#   - $1  - Filename from "Package" file
#   - $2  - SHA256 checksum from releasefile
checksum_package(){
    repo_filename=$1
    repo_sha256=$2
    repo_filepath="${_LOCAL_REPOPATH}${repo_filename}"
    if [[ -e "$repo_filepath" ]]; then

        filesum=$(sha256sum "$repo_filepath")
        file_filename=$(IFS='\t' echo $filesum | awk  '{print $2}' )
        file_sha256=$(IFS='\t' echo $filesum | awk  '{print $1}' )

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

# - getrepo_pkg_hashsums - 
# Retrive and extracts Packages filename and checksum from Package-file
#   - $1  - Repo (eg. focal, focal-security...)
#   - $2  - Section (eg. main, multiverse...)
getrepo_pkg_hashsums(){
    repo=$1
    section=$2
    package_file="${_LOCAL_REPOPATH}dists/focal/main/binary-amd64/Packages.gz"

    #Count number of packages in file
    pkg_count=$(zcat "${package_file}" | grep Filename | wc -l)
    log 6 "INFO: Retriving checksums for ${pkg_count} packages from: '${package_file}'"

    #Counter 
    n=0

    #While read Packages file and for each row (indata at the end of loop)
    while read -r  line
    do
       pwd=$(pwd)
       #If line is empty (new package)
       if [[ $line == "" ]]; then
	   # Add 1 to counter and print
           n=$(echo $n+1 | bc)
           log 7 "DEBUG: Loading checksum: ${n}/${pkg_count} - ${filename}"

	   #if filename and SHA is set, check corresponding file
           if [ -n "$filename"   ] && [ -n "$sha256" ]; then
		checksum_package "${filename}" "$sha256"
		if [[ "$?" == "0" ]]; then
                        copy_file "${_LOCAL_REPOPATH}/${filename}"
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
}


# - verify_gpg_signature -
# Verifies the GPG-signature of the "Release" file for repo
#   - $1 Reopository (eg. focal, focal-upates)
verify_gpg_signature(){
    #
    #Verify Release
    repo=$1
    gpgv --keyring $APT_KEYRING $_LOCAL_REPOPATH/dists/$repo/Release.gpg $_LOCAL_REPOPATH/dists/$repo/Release 2>&1 |\
	    grep "gpgv: Good signature from" > /dev/null 2>&1
    if [[ "$?" == 0 ]]; then
	log 7 "DEBUG: Signature Validated for ${repo}" 
	return 0
    else
        log 7 "DEBUG: Signature not validated"
	return 1
    fi

}

# - verify_files_in_dist -
# Checksum all files in /dists/$repo/$section, and compare with Release file
#   - $1  - Repo (eg. focal, focal-security...)
#   - $2  - Section (eg. main, multiverse...)
verify_files_in_dist(){
    repo=$1
    section=$2
    while read -r  line
    do
        filename=$(IFS='\t' echo $line | awk  '{print $2}' )
        sha256=$(IFS='\t' echo $line | awk  '{print $1}' )
        r_filename=$(echo $filename | sed -e "s;${_LOCAL_REPOPATH}dists/${repo}/;;g")

        line_r=$(grep "\s${r_filename}$" "$_LOCAL_REPOPATH/dists/$repo/Release" | tail -1)
        r_sha256=$(echo $line_r | awk '{print $1}')
        if [[ "$sha256" == "$r_sha256"  ]]; then
            log 6 "INFO: Filehash correct for ${filename}"
            copy_file $filename
        elif [[ "$sha256" != "$r_sha256" ]] && [ -n "$r_sha256" ]; then
            log 3 "ERROR: Filehash NOT correct for ${filename} - FILE: $sha256  -  REPO: $r_sha256"
        elif [ ! -n "$r_sha256" ]; then
            log 4 "WARNING: remote-hash not set ${filename} - FILE: $sha256  -  REPO: $r_sha256"
        else
            log 3 "ERROR: Undefined error, remote-hash not set? ${filename} - FILE: $sha256  -  REPO: $r_sha256"
    fi
    done < <(find ${_LOCAL_REPOPATH}dists/$repo/$section -type f -exec sha256sum {} \;)
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
#    if [[  "$SYSLOG_LOGLEVEL" -ge "$msg_loglevel"   ]]; then
        #logger -id verifyWsus -p "${SYSLOG_LOGFACILITY}.${msg_loglevel}" "$msg"
#    fi
}

#Full filepath
copy_file(){
   mkdir -p ${_VERIFIED_REPOPATH}
   
   #Use LS to get "clean paths" 
   file=$(ls -1 -d $1)
   source_repo=$(ls -1 -d ${LOCAL_REPOPATH})
   dest_repo=$(ls -1 -d ${VERIFIED_REPOPATH})
   newfile=$(echo $file | sed -E "s%${source_repo}%${dest_repo}%")
   #echo "copying ${file} -> ${newfile}"
   mkdir -p $(dirname $newfile)
   rsync -ra "$file" "$newfile"

}


#Path to the repo
_LOCAL_REPOPATH="${LOCAL_REPOPATH}/mirror/${MIRROR_SERVER}/ubuntu/"
#LOCAL_REPOPATH="/srv/protectera/syncfolder/ubuntu/mirror/archive.ubuntu.com/ubuntu/"
_VERIFIED_REPOPATH="${VERIFIED_REPOPATH}/mirror/${MIRROR_SERVER}/ubuntu/"

rm -rdf $VERIFIED_REPOPATH
#For each repo
for repodata in "${REPOS[@]}"; do
    #Extract REPO-name and split colon-separated list of sections
    repo=$(echo $repodata | awk -F":"  '{print $1}' )
    sections_string=$(echo $repodata | awk -F":"  '{print $2}' )
    IFS=', ' read -r -a sections <<< "$sections_string"

    log 5 "Starting reposync for REPO: ${repo} - sections queued: ${sections_string}"

    #Verify repo signature (Release file)
    verify_gpg_signature $repo
    if [[ $? != 0 ]] ; then
        log 3 "ERROR: Signature not validated, skipping REPO ${repo}"
	continue
    fi
    copy_file $_LOCAL_REPOPATH/dists/$repo/Release
    copy_file $_LOCAL_REPOPATH/dists/$repo/Release.gpg
	

    for section in "${sections[@]}"; do
        log 5 "-- ${repo} -- Section: ${section}"
	verify_files_in_dist $repo $section
        getrepo_pkg_hashsums $repo $section
    done
done
chmod -R 755 "$VERIFIED_REPOPATH"
