#!/bin/bash


#PATH to GPG keys
RPM_KEY_TO_VERIFY=(
	'./RPM-GPG-KEY-CentOS-7'
	)

#If all existing RPM gpg should be removed before verification
RPM_REMOVE_ALL_KEYS=1

#Path to repository
REPOPATH="."

#Log Facility
FACILITY="local3"


###################################################################
###################################################################
logger -s -p "${FACILITY}.info" "RPM verification started on folder ${REPOPATH} (PID: $$)"


if [[ "$REMOVE_ALL_RPM_KEYS" == "1" ]];then
	rpm -q gpg-pubkey | xargs rpm -e > /dev/null 2>&1
fi

#IMPORT RPM KEY
for key in ${RPM_KEY_TO_VERIFY[@]}; do
    rpm --import "${key}"
done



bad_files=$(find "${REPOPATH}" -name *.rpm -exec rpm -checksig {} \; | \
         	grep -v "digests signatures OK\$")

IFS="
"
for i in $bad_files; do
   logger -s -p "${FACILITY}.error" RPM signature is not OK: $i
done

logger -s -p "${FACILITY}.info" "RPM verification finnished on folder ${REPOPATH} (PID: $$)"

