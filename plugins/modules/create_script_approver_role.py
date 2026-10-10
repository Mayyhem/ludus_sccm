DOCUMENTATION = r'''
---
module: create_script_approver_role
short_description: Create the "Script Approvers" custom SCCM security role
version_added: "1.0.7"

description:
  - Creates a custom SCCM security role granting SMS Scripts Approve and
    Modify permissions on top of the Read-only Analyst role's read surface.
    Matches Microsoft's documented Script Approvers role on the SMS Scripts
    axis; broader on the read surface because Copy-CMSecurityRole inherits
    the source role's full permission set and Set-CMSecurityRolePermission
    does not clear un-named categories.
  - On subsequent runs the permission hashtable is reconciled onto the role
    unconditionally, so editing the hardcoded permission set in this module
    and re-deploying will update an existing role in the lab.

options:
    name:
        description:
        - Name of the custom security role to create.
        required: true
        type: string
    source_role_name:
        description:
        - Built-in security role to copy as the starting point.
        required: false
        type: string
        default: 'Read-only Analyst'
    site_code:
        description:
        - Site code of the SCCM deployment.
        type: string
        required: true

author:
    - chryzsh
'''

EXAMPLES = r'''
- name: Create Script Approvers security role
  mayyhem.ludus_sccm.create_script_approver_role:
    name: 'Script Approvers'
    site_code: 'PS1'
'''
