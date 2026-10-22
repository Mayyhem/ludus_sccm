# Handoff to the agent on the Ludus host

## Task and boundaries

Finish Linux validation and test this implementation on the owner's branch.
The code is in `C:\Users\domainadmin\ludus_sccm` on ps1-dev. The owner will
transfer the working files or push their test branch. Many new files are
untracked: transferring only `git diff` loses them. Do not stage, commit, push,
publish a release, or alter OpenHound/ConfigManBearPig. Read the local AGENTS.md,
[full plan](../UPGRADE_PLAN.md), and [implementation guide](version-selection.md).
Call the owner Meatbag. Keep explanations and comments in plain English.

The owner asked for code ready to test from Ludus and this handoff. Windows
implementation work does not authorize this agent to upgrade the running range.
Complete build/offline checks first. Establish which isolated range and recovery
point the owner has authorized before starting a deployment. Do not repeatedly
ask about actions already authorized in the host session.

Active lab access is limited to 10.10.10.0/24 and 10.10.11.0/24 and mayyhem.com
objects reached through those hosts. Check DNS results before active access.
Public internet access is for documentation and downloads. A different isolated
test range needs its own scope from the owner. Do not treat a research lab as a
production service, but preserve its development files and research state.

## Implemented behavior

- Shared settings: `ludus_sccm_target_version: "latest"` or an explicit understood
  release, plus `ludus_sccm_install_hotfixes: true/false`.
- Latest uses Microsoft's explicit global-availability statement and excludes
  early releases. Unknown requirements and failed evidence reads stop clearly.
- Fresh installs use selected baseline media. Installed sites avoid fresh setup
  and its uninstall/retry path. A CAS coordinator services the remaining route.
- Versioned downloads, prerequisite installation, SQL compatibility 150,
  secondary SQL 2016 SP3/2022 Express preparation, and actual secondary/passive
  readiness checks are connected to the existing roles.
- Release/hotfix waits, SQL backups/recovery media, console/client updates,
  distributed boot-image refreshes, and a fetched completion report are written.
- The sample configuration has one CAS coordinator after CAS/PS1/provider/SEC/
  passive installation. Its YAML anchor shares version settings across VMs.

Read `roles/service_hierarchy/files/*.ps1` and the common PowerShell module
before live work. The implementation is ready for validation, not proven by a
live deployment. Do not describe it as passing Ansible or integration checks yet.

## Evidence already collected

Windows local checks on October 22, 2026:

| Check | Result |
| --- | --- |
| Python release/media/route unit tests | 40 passed |
| Mocked PowerShell behavior checks | 22 passed; no network/installer calls |
| YAML and module help | 68 documents parsed; shared settings/dependencies checked |
| Windows PowerShell 5.1 parser | 64 files including 59 extracted task bodies, zero errors |
| Focused Ruff lint/format and ty | Passed; commands below |
| Git whitespace/index | Whitespace checked; no staging, commits, or pushes |
| Ansible build, syntax, action execution | Not run; no Linux controller available |
| Microsoft media extraction/installer execution | Not run |
| Fresh deploy, rerun, existing-lab upgrade | Not run |

Read-only lab inspection found CAS, PS1, SEC at 5.00.9128.1000 (2403).
CAS/PS1 databases are SQL 2022 RTM with compatibility 160. SEC has SQL 2016
Express SP2, instance CONFIGMGRSEC, database CM_SEC. Hosts run Server 2022/.NET
4.8. Existing ADK and some ODBC versions need replacement. On this date, latest
resolved 2603, not early-release 2609. Existing route: 2403 -> 2509 -> 2603;
fresh route: 2509 -> 2603. Resolve again before testing.

## Establish the controller environment

Use the existing Ludus Ansible environment. Record these outputs without secrets:

```bash
pwd
git status --short
ludus version
ansible --version
ansible-galaxy collection list
ludus ansible collection add --help
ludus range deploy --help
```

If `ansible` is not on PATH, locate the existing Ludus installation's virtual
environment and activate it. Avoid replacing Ludus's Ansible installation.
Confirm `ansible.windows`, `community.windows` and `microsoft.ad` are available.
The new code uses `ansible.windows.win_powershell` with inline scripts and
parameters; it does not require the newer `path`/`remote_src` options.

For separate Python validation, use uv and an isolated environment. This is a
validation environment, not a conversion of this Ansible repository into a
Python package. If uv is absent, use the existing verified Ansible interpreter
for standard-library tests and record unavailable optional tool checks.

```bash
uv venv .tmp/validation --python 3.13
uv pip install --python .tmp/validation/bin/python PyYAML==6.0.3 ruff==0.17.1 ty==0.0.90
.tmp/validation/bin/python -m unittest discover -s tests/unit -v
.tmp/validation/bin/python dev/check_deployment_files.py
.tmp/validation/bin/python -m dev.plan_sccm_version --help
.tmp/validation/bin/python -m dev.plan_sccm_version --target-version 2603 --current-site CAS=5.00.9128.1000 --current-site PS1=5.00.9128.1000 --current-site SEC=5.00.9128.1000
.tmp/validation/bin/python -m dev.plan_sccm_version --target-version latest
.tmp/validation/bin/python -m ruff check --isolated --target-version py38 --select E,F,I --ignore E501 plugins/module_utils plugins/action plugins/modules/sccm_version_plan.py dev tests/unit
.tmp/validation/bin/python -m ruff format --isolated --target-version py38 --check plugins/module_utils plugins/action plugins/modules/sccm_version_plan.py dev tests/unit
.tmp/validation/bin/python -m ty check --python-version 3.8 plugins/module_utils dev
git diff --check
```

The core/action support Python 3.8 syntax; use a Python version supported by the
host's Ansible release for actual controller execution. Do not run the planner
as `python dev/plan_sccm_version.py`: its documented invocation uses `-m` from
the repository root.

Windows checks, if repeated on ps1-dev:

```powershell
powershell.exe -NoProfile -File tests/powershell/Test-SccmDeployment.ps1
```

The developer's temporary interpreter was
`C:\Users\domainadmin\.tmp\ludus-sccm-validation\Scripts\python.exe`, invoked
through `uv run --no-project --python <that path>`. Extract task bodies with
`dev/check_deployment_files.py --script-directory <temporary directory>` and
parse them using `[System.Management.Automation.Language.Parser]::ParseFile`.
Never execute those extracted bodies.

## Build and check the installed artifact

Run from the repository. This preserves the declared collection version 1.0.6;
force replacement while testing so a published copy does not hide these files.

```bash
mkdir -p .tmp/collection-build .tmp/collections
ansible-galaxy collection build --force --output-path .tmp/collection-build
ansible-galaxy collection install .tmp/collection-build/mayyhem-ludus_sccm-1.0.6.tar.gz --force -p .tmp/collections
export ANSIBLE_COLLECTIONS_PATH="$PWD/.tmp/collections${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
ansible-doc mayyhem.ludus_sccm.sccm_version_plan
ansible-playbook -i localhost, tests/integration/version_plan.yml --syntax-check
ansible-playbook -i localhost, tests/integration/version_plan.yml
ansible-playbook -i localhost, tests/integration/version_plan.yml --check
ansible-playbook -i localhost, tests/integration/deployment_syntax.yml --syntax-check
```

Do not execute `deployment_syntax.yml`: it exists for `--syntax-check` only.
It imports roles that can modify guests if run against a real inventory. Dynamic
includes are not fully validated by syntax checking; inspect them and exercise
them in the live test range. The existing deployment as a whole is not claimed
to be check-mode safe. The read-only planner does support check mode.

Check the built archive contains all three servicing scripts, the shared module,
the controller action/module utilities, new task files, defaults, and docs.
Resolve any build/import/Ansible-option failures here before deploying.

To install through Ludus, serve the artifact from the Ludus host in one terminal:

```bash
python3 -m http.server 8000 --bind 127.0.0.1 --directory .tmp/collection-build
```

In another terminal on that host:

```bash
ludus ansible collection add --force http://127.0.0.1:8000/mayyhem-ludus_sccm-1.0.6.tar.gz
ludus ansible collection list
```

The URL must be reachable by the Ludus server, not just a remote CLI client.
Confirm its installed role contains `service_hierarchy` and the new scripts.
Stop the temporary HTTP server after installation. Do not fetch Galaxy's
published 1.0.6 and assume it contains the owner's unmerged work.

## Test on the authorized isolated range

Agree on a coordinated recovery point first. Retain source and test evidence
outside guest snapshots. Record the actual Ludus range/user selection; confirm
the owner intends this range, then edit a copy of `new-config.yml` as needed.
Keep its version anchor and matching domain/host names, and update the component
host list for any changed topology. Do not use `--limit`/`--only-roles` for the
first complete run; those can bypass prerequisite preparation.

```bash
ludus range config set -f new-config.yml
ludus range deploy
ludus range logs -f
```

For a rerun after VM/domain preparation has already succeeded:

```bash
ludus range deploy -t user-defined-roles
```

Test cases, each with a known starting state:

1. Fresh explicit historical release, such as 2509 with additional hotfixes false.
   Check the media/build, hierarchy roles, consoles, clients and report.
2. Fresh latest with hotfixes true. Confirm the recorded broad target, complete
   intermediate route, current hotfix catalog and full final report.
3. Rerun the same selection. No fresh site setup, site uninstall, duplicate
   update submission, console/client downgrade, or unnecessary boot-image
   refresh should occur. Existing submission roles may still report changes.
4. Hotfix false on a separately prepared older state. Confirm no additional
   fixes are submitted. Turning the switch off after fixes is not a removal test.
5. Exercise a recoverable interruption in the isolated copy. Confirm the code
   waits for an active package and fails clearly for a failed package. Correct
   the cause and use supported console Retry; never edit the site database.
6. Separately authorize the existing 2403 hierarchy test. Check backups and
   CD.Latest copies, SQL compatibility, SEC SP3/2022 upgrade/restart, each release
   hop, replication and passive readiness. Retain CAS/PS1's SQL 2022 engines.

## First places to investigate if testing fails

- **2509 media extraction:** the code uses the existing vendor self-extraction
  style `/s -d"<directory>"`. This has not been tested against downloaded 2509
  media. Check it early on an isolated guest. Verify actual folder layout and
  setup FileVersion. Do not add an unreviewed extraction dependency or skip
  signature/build checks to get past a failure.
- **Selection sharing:** localhost facts share one selection across roles in
  one Ansible invocation. Verify how this Ludus version schedules roles. Separate
  playbook processes cannot share that in-memory fact. If it launches separate
  processes, implement a deployment-specific selection record instead of
  claiming a single target across those processes. Do not reuse a stale latest
  selection from another deployment.
- **SQL and prerequisites:** verify installer package versions, native return
  codes, reboot behavior, and model/site compatibility. The named secondary
  instance is upgraded in place; a default/full SQL instance uses owner-managed
  support checks. A failed SQL upgrade needs its actual setup logs.
- **Servicing:** confirm cmdlet parameters against the installed console module,
  normal catalog synchronization, update state values, hotfix FullVersion,
  SupersededByNameList format, and child-site status. Some hotfixes only change
  clients; don't invent matching site/client version numbers.
- **Management connections:** runas must obtain a domain token with network
  access. The coordinator uses SMB admin shares, provider DCOM and endpoint
  WinRM. Endpoint source files are copied first to avoid a third-hop dependency.
- **Component scope:** check every intended console host is a registered client,
  site system or in `ludus_sccm_component_hosts`. Client push/discovery may still
  be asynchronous during the first build. Unregistered machines are not enrolled
  by final servicing; verify client push separately.
- **Boot images:** verify `-ReloadBootImage` behavior, source-version advancement,
  all original DP assignments, and rerun journal behavior. Unsupported x86/custom
  images may need owner repair. A journal is recorded only after completion.

Fix issues within this authorized implementation and update tests/docs. Report
unrelated repository bugs to the owner before broadening scope. Never replace a
failure with success, ignore prerequisite errors, or reset update database state.

## Completion evidence to leave for the owner

Save versions and command results, artifact checksum, selected target, actual
site/provider/console/client versions, unreachable endpoints, boot-image DP
status, replication state and report. Root logs/reports are fetched to
`/opt/ludus/resources/sccm/reports/<range_id>/<inventory_hostname>/`. If fetching
fails, inspect `C:\ludus\sccm` on CAS-PSS directly. SQL backups stay on SQL
hosts; CD.Latest recovery files stay on the coordinator. Also inspect
CMUpdate.log, ConfigMgrPrereq.log, sitecomp.log, failovermgr.log, client
ccmsetup.log, and SQL Setup logs as relevant.

Independently verify console access, client policy/inventory, content delivery,
PXE and collector results. Update the plan progress and guide with actual test
results. Do not mark the entire initiative complete while live checks remain.

Proposed commit after the owner's review: `Add selectable SCCM deployment and hierarchy servicing`.
The owner can use these commands; the agent must not execute them:

```bash
git switch -c test/sccm-version-selection
git add .gitignore CONTRIBUTING.md README.md galaxy.yml new-config.yml UPGRADE_PLAN.md dev docs plugins roles tests
git diff --cached --stat
git commit -m "Add selectable SCCM deployment and hierarchy servicing" -m "Select the broad release or an explicit target; prepare compatible media and prerequisites; service the hierarchy, fixes and components; verify readiness and document Ludus-host validation."
```

There is deliberately no push command. The owner chooses the remote/branch and
performs any push manually.
