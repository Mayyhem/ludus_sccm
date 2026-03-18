DOCUMENTATION = r'''
---
module: secondarysite
short_description: Install a secondary site for SCCM
version_added: "1.0.0"

description: Install a secondary SCCM site under a primary site.

options:
    parent_site_code:
        description:
        - Site code of the parent primary site
        required: true
        type: str
    sitesystem_name:
        description:
        - FQDN of the server to install the secondary site on
        required: true
        type: str
    site_code:
        description:
        - Site code for the new secondary site
        required: true
        type: str

author:
    - Chris Thompson (@_Mayyhem)
'''

EXAMPLES = r'''
- name: Install secondary site
  mayyhem.ludus_sccm.secondarysite:
    parent_site_code: '123'
    sitesystem_name: "sccm-secondary.ludus.domain"
    site_code: '456'
'''
