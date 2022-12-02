#!/bin/env python3
import yaml
import csv
import pprint
import os
import re


#Change wd to script-dir
abspath = os.path.abspath(__file__)
dname = os.path.dirname(abspath)
os.chdir(dname)


out={'ipplan_vlan_interfaces': {}, 'ipplan_hosts':{}}
with open('../data/ipplan.csv',newline='') as csvfile:
    spamreader= csv.reader(csvfile,delimiter=',', quotechar='|')
    for row in spamreader:
      try:
          if(row[1] not in out['ipplan_vlan_interfaces']):
            gatewayip = re.sub(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]",row[3],row[0])
            out['ipplan_vlan_interfaces'][row[1]] = {'ip':gatewayip, 'mode': 'static', 'description': row[2]}
          out['ipplan_hosts'][row[2]] = {'ip': "%s/32"%row[4], 'vlan': row[1]}
      except IndexError as e:
          print('Could not parse row "%s" (%s)'%(row,e))

f = open("../data/ipplan.yaml", 'w+')
yaml.dump(out,f,allow_unicode=True)



#    vdom: test22
#    ip: "172.0.10.1/30"    # ip including netmask X.X.X/XX
#    role: lan             # wan/lan/dmz
#    lldp: disable         # enable/disable
#    mode: static          # static/dhcp
#    description: "WAN interface"
#    status: "up"         # up/down
#    zone: internal
