#!/bin/bash

cd $(dirname $0)
fw=$1
vdom=$2

function apply_fw(){
    fw=$1
    echo "Applying config on firewall ${fw}"
    if [ ! -d "./${fw}" ]; then
        echo Firewall config folder does not exist
        return 1
    fi
    
    if [ ! -e "./${fw}/global.variables.yml"  ]; then
        echo "Could not find nessacary config files in folder $fw"
        return 1
    fi
    if [ -z $1 ]; then  
        # Extract all VDOMS based on configfiles
        echo "No VDOM selected, looping through all"
        pwd=$(realpath .)
        cd "${fw}"
        vdoms=()
    
        for i in $(find .  -name '*.variables.yml' -printf "%f\n"); do
            vdom=$(echo $i | sed -e "s%\.variables\.yml%%")
            if [ "$vdom"  == "global" ]; then
                continue
            fi
            echo "  - Found VDOM:$vdom  FW: $fw"
            vdoms+=("$vdom")
        done
        cd "$pwd"
    else
        vdoms+=("$2")

    fi

    ansible-playbook -vvv  ./libexec/fortigate.global.playbook -i ${fw}/host --extra-vars "@${fw}/global.variables.yml" --extra-vars "@data/ipplan.yaml" --extra-vars "@${fw}/global.interfaces.yml" 

    for i in ${vdoms[*]}; do
        ansible-playbook  ./libexec/fortigate.vdom.playbook -i ${fw}/host --extra-vars "vdom=${vdoms[0]}" --extra-vars "@data/ipplan.yaml" --extra-vars "@${fw}/${vdoms[0]}.variables.yml" --extra-vars "@${fw}/${vdoms[0]}.policy.yml"   
    done


}

function init_ansible(){
    fw=$1
    vdom=$2

}

if [ -z $1 ]; then
    echo "No firewall selected, looping through all..."
    for i in $(find . -type d -name "*.fw" -printf "%f\n"); do
        apply_fw $i $2
    done

else
   apply_fw "$1.fw" "$2"
fi
