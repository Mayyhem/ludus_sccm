DOCUMENTATION = r'''
---
module: passivesiteserver
short_description: Install a passive site server for SCCM
version_added: "1.0.0"

description: Move the content library and install a passive site server for an SCCM site.

options:
    move_contentlib_to:
        description:
        - Destination path to move the content library to
        required: true
        type: str
    sitesystem_name:
        description:
        - FQDN of the site system server to add as passive
        required: true
        type: str
    site_code:
        description:
        - Site code of the SCCM deployment
        required: true
        type: str

author:
    - Chris Thompson (@_Mayyhem)
'''

EXAMPLES = r'''
- name: Install passive site server
  mayyhem.ludus_sccm.passivesiteserver:
    move_contentlib_to: "E:\\"
    sitesystem_name: "sccm-passive.ludus.domain"
    site_code: '123'
'''
