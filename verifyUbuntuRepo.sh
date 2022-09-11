#!/bin/bash

REPOS+=( "focal:main,updates", "focal:security" )

# 1=error, 2=warning, 3=info,4-5=debug
LOGLEVEL=2
LOCAL_REPOPATH="/root/repo/ftp.acc.umu.se/ubuntu/ubuntu/ubuntu/"
VERIFIED_REPOPATH="/root/repo/ftp.acc.umu.se/ubuntu/ubuntu/ubuntu/"
#
APT_KEYRING="/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg"
#



checksum_package(){
    repo_filename=$1
    repo_sha256=$2
    repo_filepath="${LOCAL_REPOPATH}${repo_filename}"
    if [[ -e "$repo_filepath" ]]; then

        filesum=$(sha256sum "$repo_filepath")
        file_filename=$(IFS='\t' echo $filesum | awk  '{print $2}' )
        file_sha256=$(IFS='\t' echo $filesum | awk  '{print $1}' )

        #If sha256 same, and not empty
        if [[ "$repo_sha256" == "$file_sha256" ]] && [ -n "$repo_sha256" ]; then
	    log 4 "DEBUG: Correct hash for '${repo_filepath}'  [$repo_sha256=$file_sha256]"
            on_pkg_success $repo_filename
            return 0
        fi
	log 4 "DEBUG: Wrong hash for '${repo_filepath}'  [$repo_sha256=$file_sha256]"
        return 1
    else
	log 4 "DEBUG: No file found '${repo_filepath}'"
	return 10
    fi
}

#Get hashsum for all packages inside a repo
getrepo_pkg_hashsums(){
    repo=$1
    section=$2
    package_file="${LOCAL_REPOPATH}dists/focal/main/binary-amd64/Packages.gz"

    #Count number of packages in file
    pkg_count=$(zcat "${package_file}" | grep Filename | wc -l)
    log 3 "INFO: Retriving checksums for ${pkg_count} packages from: '${package_file}'"

    #Counter 
    n=0

    #While read Packages file and for each row (indata at the end of loop)
    while read -r  line
    do
       #If line is empty (new package)
       if [[ $line == "" ]]; then
	   # Add 1 to counter and print
           n=$(echo $n+1 | bc)
           log 5 "DEBUG: Loading checksum: ${n}/${pkg_count} - ${filename}"

	   #if filename and SHA is set, check corresponding file
           if [ -n "$filename"   ] && [ -n "$sha256" ]; then
		checksum_package "${filename}" "$sha256"
		if [[ "$?" == "0" ]]; then
			log 3 "INFO: Checksum correct for: ${filename}"
		elif [[ "$?" == "10" ]]; then
			log 2 "WARNING: File missing: ${filename}"
		else
			log 1 "ERROR: Checksum check FAILED for: ${filename}"
		fi
	   else
	       log 1 "ERROR: Info about package not complete NAME:${filename}  SHA256:${sha256}"
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

verify_gpg_signature(){
    #
    #Verify Release
    repo=$1
    gpgv --keyring $APT_KEYRING $LOCAL_REPOPATH/dists/$repo/Release.gpg $LOCAL_REPOPATH/dists/$repo/Release 2>&1 |\
	    grep "gpgv: Good signature from" > /dev/null 2>&1
    if [[ "$?" == 0 ]]; then
	log 4 "DEBUG: Signature Validated for ${repo}" 
	return 0
    else
        log 4 "DEBUG: Signature not validated"
	return 1
    fi

}
#
#Verify files under dist
verify_files_in_dist(){
    repo=$1
    section=$2
    while read -r  line
    do
        filename=$(IFS='\t' echo $line | awk  '{print $2}' )
        sha256=$(IFS='\t' echo $line | awk  '{print $1}' )
        r_filename=$(echo $filename | sed -e "s;${LOCAL_REPOPATH}dists/${repo}/;;g")

        line_r=$(grep "\s${r_filename}" "$LOCAL_REPOPATH/dists/$repo/Release" | tail -1)
        r_sha256=$(echo $line_r | awk '{print $1}')
        if [[ "$sha256" == "$r_sha256"  ]]; then
            log 4 "DEBUG: Filehash correct for ${filename}"
        elif [[ "$sha256" != "$r_sha256" ]] && [ -n "$r_sha256" ]; then
            log 1 "ERROR: Filehash NOT correct for ${filename} - FILE: $sha256  -  REPO: $r_sha256"
        elif [ ! -n "$r_sha256" ]; then
            log 1 "WARNING: remote-hash not set ${filename} - FILE: $sha256  -  REPO: $r_sha256"
        else
            log 1 "ERROR: Undefined error, remote-hash not set? ${filename} - FILE: $sha256  -  REPO: $r_sha256"
    fi
    done < <(find ${LOCAL_REPOPATH}dists/$repo/$section -type f -exec sha256sum {} \;)
}

#Handle log-messages
log(){
  msg_loglevel=$1
  msg=$2
  if [[  "$LOGLEVEL" -ge "$msg_loglevel"   ]]; then
     echo $msg
  fi
}

#For each repo
for repodata in "${REPOS[@]}"; do
    #Extract REPO-name and split colon-separated list of sections
    repo=$(echo $repodata | awk -F":"  '{print $1}' )
    sections_string=$(echo $repodata | awk -F":"  '{print $2}' )
    IFS=', ' read -r -a sections <<< "$sections_string"

    log 1 "Starting reposync for REPO: ${repo} - sections queued: ${sections_string}"

    #Verify repo signature (Release file)
    verify_gpg_signature $repo
    if [[ $? != 0 ]] ; then
        log 1 "ERROR: Signature not validated, skipping ${repo}"
	continue
    fi
	

    for section in "${sections[@]}"; do
        log 1 "-- ${repo} -- Starting section: ${sections_string}"
	verify_files_in_dist $repo $section
        getrepo_pkg_hashsums $repo $section
    done
done
