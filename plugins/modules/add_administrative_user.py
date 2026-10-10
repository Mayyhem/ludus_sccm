DOCUMENTATION = r'''
---
module: add_administrative_user
short_description: Add a domain account as an SCCM administrative user
version_added: "1.0.7"

description:
  - Adds a domain user or group as an SCCM administrative user with a given
    security role (built-in or custom).
  - Idempotent, if the account is already an administrative user with the
    role, no changes are made. If the account exists as an administrative
    user without the role, the role is added to it.

options:
    name:
        description:
        - Domain account or group to add, e.g. 'DOMAIN\username'.
        required: true
        type: string
    role_name:
        description:
        - Security role name to assign.
        required: true
        type: string
    site_code:
        description:
        - Site code of the SCCM deployment.
        type: string
        required: true
    security_scope_name:
        description:
        - Security scope for a newly created administrative user. Ignored
          if the administrative user already exists.
        type: string
        required: false
        default: 'All'

author:
    - chryzsh
'''

EXAMPLES = r'''
- name: Grant Script Approvers role to the Network Access Account
  mayyhem.ludus_sccm.add_administrative_user:
    name: 'DOMAIN\networkaccess'
    role_name: 'Script Approvers'
    site_code: 'PS1'
'''
