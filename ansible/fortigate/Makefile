

all:
	@./apply.sh

test:
	ansible-playbook -vvv  ./libexec/fortigate.test.playbook -i ./testfirewall.fw/host --extra-vars "@./testfirewall.fw/IMPEX.variables.yml" --extra-vars "@data/ipplan.yaml" --extra-vars "@./testfirewall.fw/IMPEX.policy.yml" 
