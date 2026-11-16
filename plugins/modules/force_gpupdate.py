DOCUMENTATION = r'''
---
module: force_gpupdate
short_description: Force gpupdate on Certain OUs
version_added: "1.0.0"

description:
- Refresh computer policy on the selected domain computers.
- Uses PowerShell remoting for remote computers and a local gpupdate for the calling computer.
- WinRM must be reachable with the calling domain account. Check mode lists targets without refreshing policy.

options:
    workstations:
        description: 
        - True/False to force gpupdate on workstations
        required: true
        type: boolean
    servers:
        description: 
        - True/False to force gpupdate on servers
        required: true
        type: boolean
    domain_controllers:
        description:
        - True/False to force gpupdate on domain controllers
        required: true
        type: boolean
        

author:
    - Zach Stein (@ySynzack)
'''

EXAMPLES = r'''
- name: Force gpupdate on OUs
  mayyhem.ludus_sccm.force_gpupdate:
    workstations: true
    servers: true
    domain_controllers: false
'''
