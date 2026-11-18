# SCCM version selection and lab upgrade plan

Plan agreed on 2026-10-21. This document describes the intended work, the reasons for it, and the evidence needed before calling it complete. It is not a claim that the features below already exist.

## Clean run 011 acceptance passed after recorded interventions: 2603 with hotfixes, November 18, 11:14 EST

The run started from zero and finished at 2603 (2509 baseline upgraded in place) with hotfixes, and independent native/functional acceptance passed. Status PASSED_AFTER_INTERVENTION; it is not unattended proof. Recorded interventions (run.json ExternalInterventions): ConfigCorrection, LudusPlatformRedeploy, SccmServicingCorrection, SourceCorrection, UserDefinedRolesRerun. Two were code fixes made mid-run: background domain-admin tasks no longer load the profile, and queued hotfix downloads get a native catalog check. One manual native Check for Updates was issued during diagnosis. Proof and final reports: .tmp/evidence/unattended/run-011/acceptance-summary.json and run.json. Only user/range cthompson was accessed. Nothing was staged, committed, pushed or published.

## Run 011: queued hotfix downloads are now handed to the service connection point, November 17, 23:50 EST

Run 011 installed every site and role and upgraded the hierarchy to 2603, then hotfix servicing timed out after 3 hours waiting for KB38232642 to download. The download was requested 3 minutes after the service connection point (cas-scp) last synced; the SCP fetches queued downloads only during a sync, and nothing triggered another one. One native Check for Updates on cas-pss made it fetch the hotfix in 16 seconds. Install-SccmUpdatePackage now requests that native catalog check every 10 minutes while a requested download is still queued; tests/powershell/Test-SccmDeployment.ps1 covers it. The manual check and the code change are recorded in run.json as an SccmServicingCorrection, so run 011 cannot count as unattended proof. Evidence: .tmp/evidence/unattended/run-011/hotfix-diag.

## Run 011: background domain-admin tasks no longer load the profile, November 17, 14:41 EST

After the November Windows update KB5131090, ps1-pss failed prepare_sccm twice with Start-Process: registry key marked for deletion. A harmless probe reproduced it 3/3 on ps1-pss (20348.5870) and 0/3 on unpatched cas-pss: a background (async) runas job that loads the domain admin profile loses that hive as soon as the become launcher exits. Without the profile flag (logon_flags=) Start-Process, HKCU writes and domain network access all work on both. The five async domain-admin tasks (prerequisites, media, passive and secondary readiness, phase runner) and the secondary console include now use logon_flags=; tests/unit/test_async_become.py guards it. Run 011 continues with a user-defined-roles rerun, recorded as a SourceCorrection. Evidence: .tmp/evidence/unattended/run-011/profile-diag.

## Clean run 011 config correction: November Windows update, November 17, 12:02 EST

The first full run 011 deploy stopped at windows_base on ps1-pss before any SCCM product role: the pinned October Windows Server 2022 cumulative update KB5126655 is superseded by November KB5131090 (released November 10, after run 010), so Windows Update no longer offers it. The run config now pins KB5131090 instead for ps1-pss and ps1-sms (KB5122882 kept), recorded as a ConfigCorrection intervention, and one full redeploy started without teardown. new-config.yml still pins KB5126655 and will fail the same way until updated.

## Clean run 011 deploying, November 17, 10:01 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 10a520539fd307f15fdf2226a1e03fee0789b248b607ac0a121dc233a7baeda4. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-011. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 011 preparation: fresh 2603 with hotfixes, November 17, 10:01 EST

Owner request 2026-11-17: tear down and install 2603 from scratch. The in-place 2509 to 2603 upgrade of the run 010 lab finished CAS, PS1 and SEC at 5.00.9146.1000 but stopped at passive ps1-psv: PS1's update reinstalled the SMS Provider on ps1-psv, which replaced the shared bin\x64 binaries (smsexec 9146.1009) but left FailOverMgr.dll at 9141.1002, so SMS_FAILOVER_MANAGER failed to load (error 127) and could not run the passive upgrade job. Run 005 (2509 to 2609, same layout) did not hit this. Run 011 rebuilds from zero with config .tmp/cthompson-2603-cmbp.yml: 2509 baseline, upgrade to 2603, applicable hotfixes, custom role, two administrators and the PS1-DEV primary user. Evidence: .tmp/evidence/unattended/run-011 and .tmp/evidence/upgrade-2603.

## ConfigManBearPig lab setup added and proven on the run 010 lab, November 12, 10:50 EST

At the owner's request, service_hierarchy can now add collector-testing RBAC and user device affinity after completion: `ludus_sccm_custom_security_roles`, `ludus_sccm_administrative_users` (a password creates the domain account) and `ludus_sccm_primary_users`, all empty by default. The sample sets them on the CAS: `Custom Role` (a copy of Read-only Analyst), `networkaccess` as Full Administrator, a new `roanalyst` as Read-only Analyst, and `domainuser` as PS1-DEV's primary user. These were applied to the run 010 lab by rerunning only service_hierarchy on cas-pss (no teardown; config .tmp/cthompson-2509-hotfix-cmbp.yml). A second rerun changed nothing. ConfigManBearPig's live integration tests, run from this host with a /tmp-only collector fix and updated fixtures, then passed 93, failed 3 and skipped 1. The 3 failures are ConfigManBearPig-side: the AdminService relay case predates 2509, and two SameHostAs cases need the collector to get client hostnames without running on PS1-DEV. Evidence: .tmp/evidence/cmbp-lab-setup.

## Clean run 010 acceptance passed: 2509 with hotfixes, November 10, 16:58 EST

The deployment from zero completed at 2509 with automatic secondary recovery and client setup reruns, and independent native/functional acceptance passed, including a CAS catalog check that hotfixes installed with none running or failed and SEC reports its updates current. Proof, frozen source/config/archive, zero-lab state and final native reports are in .tmp/evidence/unattended/run-010/acceptance-summary.json and run.json. No external deployment recovery, restart or source correction was used. Only user/range cthompson was accessed. Nothing was staged, committed, pushed or published.

## Clean run 010 deploying, November 09, 19:10 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 9fbfbd2d283ddf4e8bbe461b2997d876644765d57d07e24061cb65a947275f0f. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-010. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 010 preparation: early Ludus setup recovery and app cleanup, November 09, 19:09 EST

Run 009 was stopped on November 9: the Ludus built-in Sysprep failed on ps1-dev and on server ps1-sms. Cause found on the guests: the months-old templates boot with internet and the Store/Edge update built-in apps for localuser before Sysprep runs; Sysprep rejects any app installed for one user but not provisioned (0x80073cf2) and names only the first, while Ludus removes that one package and retries once. ps1-dev had 44 such apps; ps1-sms (2 GB) timed out starting its retry. Ludus then silently skipped every role on the dropped VMs and started SCCM roles without the SMS Provider server. Failed copies also keep the template evaluation clock (Windows 11 expired, Server about November 18); successful Sysprep resets it to 180 days. The owner keeps templates and licenses as they are. The driver now watches the Ludus log before any SCCM task: a Windows VM dropped from the play (confirmed on two polls) stops the deploy, the per-user-only apps on VMs that failed in the Sysprep play are removed with .tmp/clear-peruser-apps.yml, and one full redeploy starts (at most two). Scored PASSED_AFTER_PLATFORM_RETRY when used. Evidence: .tmp/evidence/unattended/run-010.

## Clean run 009 deploying, November 09, 14:16 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 8d346844a46cdffc5badf55170d0effc7d85b15769e0723cbb4b671896d944fd. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-009. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 009 preparation: Sysprep recovery and report copy check, November 09, 14:15 EST

Run 008 built 2509 from zero, installed all four hotfixes with automatic SEC recovery, and the client setup reruns finished 12 clients in minutes each, but the Ludus built-in Sysprep failed on Windows 11 ps1-dev (Microsoft.WidgetsPlatformRuntime installed for a user but not provisioned for all users, still failing after the Ludus package removal and retry), so final completion stopped on that unreachable client. Redeploying only ps1-dev and rerunning service_hierarchy completed the lab, and read-only acceptance passed. Agreed with the owner (November 9): keep Sysprep on every VM; the clean-run driver now redeploys a VM whose only failure is the Ludus Sysprep step before any SCCM role ran on it (at most two tries per VM), then reruns service_hierarchy on the CAS, scored PASSED_AFTER_PLATFORM_RETRY. The servicing report copy now checks its controller folder first and only warns when it cannot be created. 49 controller, 180 helper, 13 completion, 16 provider and the new report-copy checks passed. Evidence: .tmp/evidence/unattended/run-009.

## Clean run 008 outcome, Sysprep recovery and report copy check, November 09

Run 008 (from zero, 2509 with hotfixes) completed the release, all four hotfixes with
automatic SEC recovery after each, and client setup reruns (12 clients in about 3-4
minutes each instead of 90-minute timeouts). It failed at final completion (November 7,
12:25 UTC) because the Ludus built-in Sysprep step failed on Windows 11 ps1-dev:
Microsoft.WidgetsPlatformRuntime was installed for a user but not provisioned for all
users (0x80073cf2), still failing after the Ludus package removal and retry. ps1-dev
never joined the domain and was the one unreachable client. This was the first Sysprep
failure in eight runs. Status: FAILED_PLATFORM_SYSPREP, not unattended proof.

Lab recovery on November 9 (guest redeploys only): `range deploy --limit cthompson-ps1-dev`
(SUCCESS in 20 minutes), then service_hierarchy on cas-pss (SUCCESS in 23 minutes).
Read-only acceptance passed: 13 clients at 5.00.9141.1041, CAS/PS1/SEC at 5.00.9141.1000.
Evidence: .tmp/evidence/unattended/run-008 (ludus-error.log, recovery-*.log,
final-acceptance).

Agreed with the owner on November 9:

- Sysprep stays on for every VM. Servers need it (clones would share the template machine
  SID, which the first DC turns into the domain SID, and would share WSUS client IDs).
- The clean-run driver now recovers automatically when the only failed VMs failed in the
  Ludus Sysprep step before any SCCM role ran on them (the CAS completion failure that
  follows is allowed). It redeploys only those VMs (at most two tries each), reruns
  service_hierarchy on the CAS once, and records each step. Such a pass is scored
  PASSED_AFTER_PLATFORM_RETRY. The README documents the same two commands.
- The servicing report copy (service_hierarchy `report.yml`) now checks that the
  controller folder can be created first. If not, it skips the copy and prints one warning
  naming where the reports are on the server; it never fails the deploy. An empty
  `ludus_sccm_artifacts_directory` turns the copy off. The test range config keeps its
  existing path (owner decision), so this lab shows the warning; acceptance still fetches
  reports into the project.

Controller checks: 49 unit tests, version_plan, the new report_fetch integration test
(writable, uncreatable and disabled destinations) and syntax checks passed. PowerShell is
unchanged since run 008 (180 helper, 13 completion, 16 provider checks).

## Clean run 008 deploying, November 06, 09:59 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 9843d8a0ff280c4aaddb117147bf6a3f65ce96f887543c1ad3f75452ff5c6768. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-008. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 008 preparation: client setup reruns and backup pruning, November 06, 09:59 EST

Run 007 built 2509 from zero (after one Ludus platform redeploy before any SCCM role), installed all four hotfixes and recovered SEC automatically after each, then failed at completion: native client setup applied only one of the last two client patches per run, and completion waited out the 90-minute timeout on 10 clients. Completion now reruns setup (at most three runs per client) when the setup service run exits 0 below the production version, and each verified database backup now removes older automation-named backups of that database. On the run 007 lab the targeted completion finished (all 13 clients at 5.00.9141.1041) and read-only acceptance passed; pruning freed about 16.5 GB. The owner approved (November 6) tearing down only user/range cthompson and rebuilding from zero. 49 controller, 180 helper, 13 completion and 16 provider checks passed. Evidence: .tmp/evidence/unattended/run-008.

## Clean run 007 outcome and client completion fix, November 05, 16:45 EST

Run 007 (2509 from zero, cthompson only) needed one Ludus platform redeploy (DC OU step ran before AD Web Services started; no SCCM role had run). It then built the hierarchy, installed all four 2509 hotfixes (KB36495448, KB36419072, KB37864969, KB39398030) and recovered secondary SEC automatically after each one, using the single SMS_EXECUTIVE restart each time. Completion then failed: one ccmsetup run applied only rollup KB37864969 (client 5.00.9141.1032) and skipped KB39398030 as not applicable, and the code waited 90 minutes per client for 1041 (10 clients, about 15 hours).

Fixes: completion reruns client setup (at most three runs) once the setup service run has exited 0 after this launch and the client is still lower; Get-SccmClientState now reports SetupExitCode and SetupFinishedUtc and ignores the launcher's own exit line. Backup-SccmDatabase keeps only the newest verified CM_<site>_ludus_*.bak per database. Windows checks: 180 helper, 13 completion, 16 provider, 20 files parsed; 49 controller tests.

On the run 007 lab, a targeted service_hierarchy redeploy with the fix succeeded (13 clients 5.00.9141.1041) and read-only acceptance passed; the live backup cleanup freed 16.5 GB. Not yet proven: a from-zero run with these fixes (run 008 needs owner approval for teardown). Evidence: .tmp/evidence/unattended/run-007.

## Clean run 007 deploying, November 03, 20:35 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 571f15bebde07d102192d6d900436e2bcf379005b6ce8a8761ece37b6f5a99cd. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-007. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 007 preparation: automatic secondary recovery, November 03, 20:34 EST

Run 006 built 2509 from zero and installed hotfix KB36495448 at CAS and PS1, then stopped by design because secondary SEC never receives a same-build hotfix by itself. The owner asked (November 3) to make that recovery automatic, test it, then tear down and rebuild from scratch, cthompson range only. Complete-SccmSecondaryUpdates now submits native Recover Secondary Site (after its existing replication, identity, idle-setup and backup guards) and waits for SEC to report current. On the run 006 lab the recovery completed, but the SEC replication sender stopped after a mid-setup component restart until SMS_EXECUTIVE was restarted; the wait now restarts it once when links stay unhealthy for 20 minutes after setup. The remaining servicing, console and completion phases were then exercised on that lab before this teardown. 49 controller, 175 helper, 11 completion and 16 provider checks passed. Evidence: .tmp/evidence/unattended/run-007.

## Clean run 006 stopped at the secondary hotfix, November 03, 01:56 EST

The 2509 build from zero completed across the hierarchy. One applicable hotfix, Configuration Manager 2509 Hotfix (KB36495448), downloaded, passed prerequisites and installed at CAS and PS1 after database backups and recovery media copies. One minute later the preview found secondary SEC missing that package after the parent had already reported, so the new stop-and-ask check stopped servicing as designed. Recover Secondary Site was not submitted. The console update after a hotfix, final completion and acceptance were not reached, and the automatic restart loop did not fire. The range is left as is (Ludus state ERROR). Evidence: .tmp/evidence/unattended/run-006/OUTCOME.txt.

## Clean run 006 deploying, November 02, 17:27 EST

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 04b3bd54dbb516b862a1adcb6a95cb1cb7fe65f7bd745cf74cd3ab34503510c6. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-006. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean run 006 preparation: 2509 with hotfixes, November 02, 17:26 EST

Run 005 passed but its 2609 target had no hotfixes, so hotfix servicing, the console update after a hotfix and same-build secondary handling were never exercised live. The owner approved (November 2) tearing down only user/range cthompson and building from zero at 2509 with hotfixes enabled; 2509 hotfixes are in the Microsoft catalog. Changes since run 005: a same-build secondary that lacks hotfix packages now stops with the missing list instead of submitting Recover Secondary Site, and windows_base fails if any selected KB is not installed. 49 controller, 173 helper, 11 completion and 16 provider checks passed. The 2509 setting is only in .tmp/cthompson-2509-hotfix.yml; new-config.yml still targets latest. Evidence: .tmp/evidence/unattended/run-006.

## Clean unattended run 005 acceptance passed, October 31, 21:39 EDT

The qualifying deployment from zero completed and independent native/functional acceptance passed. Proof, frozen source/config/archive, zero-lab state and final native reports are in .tmp/evidence/unattended/run-005/acceptance-summary.json and run.json. No external deployment recovery, restart or source correction was used. Only user/range cthompson was accessed. Nothing was staged, committed, pushed or published.

## Clean unattended run 005 deploying, October 31, 12:20 EDT

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 8fd5e413e9cdf8c23c601887becac0353e8d19c5ec3f5481a2a44eb17c006d18. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-005. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean unattended run 005 preparation, October 31, 12:19 EDT

Clean run 004 passed the windows_base restart that stopped run 003 and ran about 8.5 hours: all sites installed, upgraded 2509 to 2609, applied hotfixes and passed site, management point and distribution point health. Final verification then stopped: the CAS read every registered SMS Provider over DCOM, and the passive site server ps1-psv refuses DCOM from every remote host (CAS and ps1-pss alike) while WinRM and its native HA status are healthy. The hierarchy does not need that cross-site access. Final verification now reads each provider build on its own host over WinRM, and every per-site provider choice prefers the provider on the active site server instead of the first one listed. Only SccmDeployment.psm1 and Complete-SccmDeployment.ps1 changed since run 004; 49 controller, 172 helper, 11 completion and 16 provider checks passed and the corrected reads returned build 9152 from all four live providers. Latest is resolved again with applicable hotfixes enabled. Under the owner standing authorization, only user/range cthompson is removed and redeployed from zero. Evidence: .tmp/evidence/unattended/run-005.

## Clean unattended run 004 deploying, October 30, 19:29 EDT

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 9b6e3042d19e5e0c112966004ac61eeb4b75bdace58f55003ab989af7762e983. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-004. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean unattended run 004 preparation, October 30, 19:28 EDT

Clean run 003 failed after 2 hours 20 minutes, before any SCCM work: right after windows_base restarted ps1-lib to finish installing WebDAV, the next WinRM connection was lost with "registry key marked for deletion". That restart is the first boot with domain admin auto-logon, so Windows was still building that profile. The restart now waits until two minutes of uptime and, while auto-logon is pending, until the desktop shell starts (at most five minutes of uptime). Only roles/windows_base/tasks/enable_webdav.yml changed since run 003; 49 controller checks passed, the role file parsed and the settle check returned ready on a live guest. The run 002 replication wait and boundary link fixes are unchanged. Latest was resolved again with applicable hotfixes enabled. Under the owner standing authorization, only user/range cthompson is removed and redeployed from zero. Evidence: .tmp/evidence/unattended/run-004.

## Clean unattended run 003 deploying, October 30, 17:05 EDT

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 626156136dbd4a8d5d1e1ae57efd2fe88dfc411710caba63027d520d2055cdcd. Any deployment repair requires another clean run. Inputs and acceptance output are in .tmp/evidence/unattended/run-003. Do not submit another deploy or alter its executable source while it runs. This is in-progress validation, not unattended acceptance.

## Clean unattended run 003 preparation, October 30, 17:04 EDT

Run 002 failed only at its first release step: the replication check saw two briefly unready groups and stopped on one read. The groups settled with no intervention. Assert-SccmReplication now waits up to 60 minutes for every group to be initialized with zero failed/degraded syncs and still fails, naming the groups, if they stay unready. Run 002 also installed no clients: the AD site boundary appeared 18 seconds after create_boundary_group tried to link it and the module ignored the failure. The module now waits for the boundary, verifies membership and fails visibly. Diagnostic-003 resumed only service_hierarchy on the run-002 lab, completed 2509 to 2609 with the remote SMS Provider present, and, after the corrected module linked the boundary, passed independent acceptance; it is not unattended proof. 49 controller, 169 helper, 11 completion and 16 provider checks passed. Latest was resolved again with applicable hotfixes enabled. The owner-authorized full rebuild of only user/range cthompson will run every configured role from zero. Evidence: .tmp/evidence/unattended/run-003.

## Run 002 failed; two fixes found and tested, October 30, 14:30 EDT

Run 002 (full build from zero) built all 15 guests and every role through the
SMS Provider, then stopped at the first 2509 to 2609 release step on October 29
at 20:46 EDT. It is FAILED and is not unattended proof. Evidence:
.tmp/evidence/unattended/run-002 (ludus-final.log and post-failure-*.log).

Fix 1, replication check. The release step read replication status once and
stopped because two CAS/PS1 groups were briefly unready. All 86 groups were
healthy the next morning with no intervention. Assert-SccmReplication now waits
up to 60 minutes (one read per minute), logs the names of unready groups, and
still fails, naming them, if they stay unready. Three new mocked checks cover
settle, persistent and ready cases (169 helper checks total).

Fix 2, missing clients. Run 002 never installed any SCCM client. The role
created the PS1 site-assignment boundary group at 18:58:52 EDT, but forest
discovery created the AD site boundary at 18:59:10. The add ran in between,
failed, and create_boundary_group ignored every add error as "already linked".
No computer was in an assigned boundary, so automatic client push never queued
a request. The module now waits up to 5 minutes for the boundary, checks real
membership, and fails visibly if it cannot link it; the task's existing five
retries remain. On the diagnostic lab the corrected module linked the boundary,
a second run reported no change, a missing boundary failed with a clear
message, and push installed 5.00.9152.1006 on all 13 expected machines within
minutes (DC is excluded by configuration).

Diagnostic-003 (not proof) resumed only service_hierarchy on the run-002 lab.
It upgraded CAS, PS1 and SEC to 2609 with the remote provider present and
passed the replication check, but acceptance found no clients (fix 2 above).
A second service_hierarchy resume with the corrected collection is verifying
end-of-build acceptance. Then a clean run 003 from zero follows, using the
owner's existing teardown permission for user/range cthompson only.
Evidence: .tmp/evidence/unattended/diagnostic-003.

Report fetch note: ludus_sccm_artifacts_directory in the range config points
into /home/cthompson, which the ludus service account cannot traverse. The fetch
is ignored on failure and reports stay in C:\ludus\sccm on each server; they
are copied into this project afterwards with the local Ansible fetch.

## Qualifying run 002 is active; provider readiness corrected, October 29, 15:56 EDT

The scoped API confirmed DESTROYED with zero VMs, and exactly one full unfiltered
ludus --user cthompson --range cthompson range deploy invocation started October 29
at 15:27:42 EDT. Frozen archive SHA256:
63ae708553c01e43856e1f73285f342ff07a1b16ad02cb06d549f1c58e3aa641.
Full configuration SHA256 remains
38312e6973157b72d16161c27acf7d9440fb67a7075dc880216ad2ef04250ae5.
Latest was resolved again to broadly available 2609 from baseline 2509, with
applicable fixes enabled. No external deployment intervention has occurred.

New source fixes before this freeze: install_sms probes both parent registration
and the actual target namespace, computer/domain, site/server identity and build.
A stale registration cannot be skipped as success or blindly reinstalled. Missing
ADK Deployment Tools or a different installed site also prevents setup. A prepared
target can finish active native installation work before SDK setup; completion
requires the actual provider to match its parent. prep_sms now normally reboots
after Windows feature changes, matching site-server preparation. Validation:
49 controller, 166 helper, 11 completion-restart and 16 new mocked provider checks;
10 PowerShell parses, expanded role syntax and collection build/install passed.
The live read-only probe rejected the diagnostic's registered-but-missing
namespace with ADK present. No native status, queue, identity or SQL data was
manually changed. That diagnostic did not pass overall acceptance.

Only this clean run can establish unattended proof. All 15 own guests have been
created. Ludus is completing automatic Sysprep/WinRM preparation; expected
connection losses have entered its existing rescue handling. Do not infer a
terminal failure from conditional fail-task names or rescued connection loss.
Observe the actual range outcome. Do not change executable source, issue another
deploy, or restart guests externally while qualifying. The running saved driver
is .tmp/start-verified-clean-rebuild.py (exec session 22022), with its own lock
clean-run-002-driver.lock. It will run independent final native/functional
acceptance after SUCCESS. Earlier drivers/observers are stopped. Evidence and
zero-lab proof are under .tmp/evidence/unattended/run-002. Unattended acceptance
is still pending; preserve historical failed and diagnostic evidence.

## Clean unattended run 002 deploying, October 29, 15:27 EDT

The scoped API confirmed DESTROYED with zero VMs. One full unfiltered ludus --user cthompson --range cthompson range deploy invocation has started using final archive 63ae708553c01e43856e1f73285f342ff07a1b16ad02cb06d549f1c58e3aa641. No external intervention is authorized as proof: any deployment repair requires another clean run. Source/config/zero-lab inputs and all acceptance output remain in .tmp/evidence/unattended/run-002. Continue observing this run; do not submit another deploy or alter its executable source. This is in-progress validation, not unattended acceptance.

## Clean unattended run 002 preparation, October 29, 15:27 EDT

The owner-authorized full rebuild of only user/range cthompson is being prepared after validated provider preflight/readiness corrections. Diagnostic-002 did not pass overall acceptance: its targeted resumes omitted provider prerequisites and left an incomplete registration. That evidence is retained; it is not unattended proof. The corrected probe rejects that state, and 49 controller, 166 helper, 11 completion and 16 provider fixture checks passed. Current broad target was resolved again to 2609 from baseline 2509 with applicable hotfixes enabled. The full unfiltered build will test every configured role in its normal dependency order. Evidence will be retained in .tmp/evidence/unattended/run-002.

## Diagnostic prerequisite omission corrected, October 29, 14:46 EDT

The source prep_sms role already includes version-selected ADK/WinPE preparation,
and both new-config.yml and the assigned full configuration correctly make
install_sms depend on prep_sms. The targeted diagnostic role selection omitted
that unfinished prerequisite too. No production change is needed to add it.
Native SDK setup stopped at the explicit missing-ADK error before registering
PS1-SMS. Its coordinator was aborted through the scoped Ludus API. A saved normal
Ansible restart of PS1-PSS passed guards for the exact terminal prerequisite
failure, online remote CM_PS1, no running local SQL, no active site update and
retained automatic site-service startup. Normal site-manager startup passed
after boot; no process or SQL service was directly forced.

Resume only the existing prep_sms, install_sms and service_hierarchy roles
together. Their prerequisite/install code and full configuration remain frozen
and unchanged. Finish provider-native path/build checks and independent complete
acceptance before restarting the stopped clean-rebuild driver. The API schema
and binary-path corrections affect only the independent observer. This remains
diagnostic work and not unattended proof. Evidence is retained in diagnostic-002,
including provider-native-setup-progress.log and restart-after-failed-sdk.log.

## Diagnostic resume omitted the SMS provider, October 29, 14:29 EDT

Independent native/functional acceptance confirmed the three-site deployment,
13 installed clients, both consoles, remote SCP/MP/DP builds, MP HTTP, PXE/TFTP,
and strictly newer DEV hardware inventory. It did not pass overall acceptance:
PS1-SMS has no root\SMS\site_PS1 provider namespace. The earlier targeted
resume selected install_secondary_site and service_hierarchy, omitting install_sms
which the full range configuration already requests. No install_sms tasks occur
in the retained failed/diagnostic run histories. This diagnostic orchestration
omission must be completed through the normal Ludus role before any clean rebuild.

The independent reader also used an incomplete MP binary path: SEC's IIS SMS_MP
application is under C:\Windows\CCM\SMS_MP because it has a full installed
client. Verify its binary from that registered directory's parent. Correct the
reader without weakening version checks. The API reader's separate omitted-false
isRouter issue was corrected and its original failed evidence retained. Production
executable source and full configuration remain unchanged. The clean-rebuild
driver stopped safely before teardown and remains stopped. Finish the provider
role and normal servicing verification, then rerun independent acceptance before
restarting the gated driver. Fresh unattended proof remains incomplete.

## Four guarded restarts and automatic resume passed, October 29, 14:14 EDT

The normal deployment completed all four native client restarts serially: CAS-DB,
MONITOR, PS1-DB and PS1-DP. Each passed its post-boot checkpoint check. Ansible
then resumed the component coordinator on attempt 2 without another deploy,
manual restart/recovery play, or source correction. Exact scoped Ludus task
history is retained in diagnostic-002/ludus.log and observations.jsonl. Boot-image
completion and independent acceptance remain pending; this diagnostic still does
not establish a fresh unattended build. Continue the existing diagnostic observer
and gated clean-rebuild driver rather than starting another coordinator.

## Automatic client restart path exercised, October 29, 14:06 EDT

Diagnostic-002's first component pass finished with three sites, two consoles,
13 installed clients (including SEC), no failures, and four native client restart
requests at 5.00.9152.1006: CAS-DB, MONITOR, PS1-DB and PS1-DP. All seven role
summaries had already returned green. The normal deployment's Ansible flow
restarted CAS-DB, verified that its checkpoint cleared, and advanced to MONITOR.
No separate restart/recovery play or source correction was submitted. Evidence:
.tmp/evidence/unattended/diagnostic-002/component-client-checkpoint-detail.log.

Finish all four guarded serial restarts, the resumed component pass, boot images
and independent native/functional acceptance. This diagnostic is not proof of a
fresh unattended deployment. The gated own-range clean-rebuild driver remains
waiting for complete diagnostic acceptance; executable source is unchanged.

## Native component retry passed, October 29, 13:30 EDT

Diagnostic-002 completed two accepted, settled native hotfix scans with no
applicable registered fix. CAS-SCP restarted through its own component-manager
reinstall without intervention. PS1-MP initially retained a critical summary
while its control component was stopped for upgrade. At the scheduled 13:22
poll, the native component manager started its queued role reset. Its client
prerequisite reached 5.00.9152.1006 with exit 0, and MP MSI completed at 13:28
with exit 0 and version 5.00.9152.1000. All seven checked role summaries are
now green; the coordinator has advanced to client completion. No component
manager/service restart, secondary recovery, status edit or source change was
required. Do not add a retry solely to bypass these normal bounded native waits.

Client, console, boot-image and independent functional acceptance remain pending.
The diagnostic observer and gated clean-rebuild driver remain active. A fresh
qualifying run from zero has not yet started.

## Diagnostic hierarchy upgraded normally, October 29, 12:56 EDT

Diagnostic-002 has upgraded CAS, PS1 and SEC to 5.00.9152.1000 through the
normal deployment roles. SEC setup completed at 12:39 EDT; its parent package
history initially remained at content replication and its consistency flag was
0. By 12:55 both providers and the parent's native consistency function reported
1, with the package installed (196612). No reporting retry, service restart,
recovery, native queue/status edit or source correction was needed.

The existing coordinator has advanced to applicable hotfix servicing. Component,
client, console, boot-image and functional acceptance are still pending. The
frozen diagnostic source remains unchanged. The read-only acceptance observer
and guarded clean-rebuild driver are still active; the latter may proceed only
after the complete diagnostic acceptance passes and all scope/source/configuration
guards pass. A diagnostic success alone will not establish unattended deployment.

## Active diagnostic deployment, October 29, 10:49 EDT

Only cthompson's normal install_secondary_site and service_hierarchy roles are
running in diagnostic-002. Source archive bf70a7586f70cf379e3832db76d7709fc5174a185be1ed55ef379c000573be9f
is installed; its executable manifest and archive are preserved with that run.
No executable source changed after this invocation. Console readiness passed;
SEC's prerequisites, package transfer, SQL 2022 Express installation and its
named-instance connection test passed. Native setup advanced past SQL discovery
without intervention and is installing database schema/table keys (10:46 EDT).

Setup emitted the same MSSQLSERVER discovery/ODBC trailing-comma errors as the
prior baseline installation. Parent and bootstrap SQLServicePort/SQLSSBPort are
already 1433/4022. Historical own-range evidence shows this sequence from about
19:35 through later setup completion at 20:12 on October 26 without a port,
alias, registry, queue or SQL repair. Do not change ports or interrupt setup
solely because of these messages; wait for real native progress/terminal state.

The observer .tmp/verify-unattended-run.py diagnostic-002 --wait is running. It
submits no deployment or repair. After Ludus SUCCESS it validates the scoped API
inventory and DNS, exact frozen source/artifact, fetched final report, native
components, remote-role binaries, MP/TFTP and newly received hardware inventory.
Its own evidence/acceptance logs remain in diagnostic-002. Failures stop its
checks; even a verified diagnostic lab does not prove a clean unattended run.
After diagnosis succeeds, freeze final source, resolve latest again, and use the
owner-authorized clean teardown/redeploy for run-002 with one full unfiltered
invocation. Fresh qualifying acceptance remains incomplete.

## Diagnostic console identity correction, October 29, 2026

Diagnostic resume 001 passed native passive readiness and automatically restarted
SEC after enabling its Windows features. It stopped before secondary-site
creation because the servicing-console guard used MSI uninstall DisplayVersion
1000 while SMS_Identification advertised native console revision 1200.

Readback confirmed both CAS and PS1 already had native AdminConsoleVersion
5.2509.1036.1200 under ConfigMgr10\Setup, including the CAS before any updater
trial. Their MSI inventory and Tools\ConsoleSetup\AdminConsole.msi remain
5.2509.1036.1000. The console executable and individual assemblies also carry
different component build numbers; neither is the aggregate product version.

Get-SccmConsoleVersion now reads the unique native AdminConsoleVersion after
confirming one installed MSI record, the registered executable's presence and
consistent release metadata. Missing, ambiguous, orphaned or older native
registrations fail closed. Independent acceptance reads this native field and
retains the MSI version separately. Normal ConsoleSetup installation remains;
console installer calls now have a 30-minute bound. Exact provider-version and
restart checks remain unchanged.

Exploratory saved Ansible trials included a native updater call: its invalid
Quiet argument exited 2; corrected /q exited 0 but did not change the MSI record.
That unnecessary updater branch was removed after identifying the native version
source. No native state/queue/key edits or forced service operations occurred.

Validation passed 49 controller checks, 166 isolated helper checks, 11 isolated
completion checks and eight PowerShell parses. The corrected live production phase passed. The collection was installed only
for cthompson (archive SHA256
bf70a7586f70cf379e3832db76d7709fc5174a185be1ed55ef379c000573be9f).
A remaining-role diagnostic deployment started through Ludus with only
install_secondary_site and service_hierarchy selected; its evidence is in
.tmp/evidence/unattended/diagnostic-002. Evidence for the console correction: .tmp/evidence/unattended/diagnostic-001,
especially console-version-registry-and-cas.log and console-native-identity-regression.log.
This remains diagnostic development; a new full rebuild from zero is required.

## Clean unattended run 001 failed; passive validation fix under test, October 29, 2026

The clean run began from the scoped API's DESTROYED state with zero VMs and one
full deployment invocation on October 28 at 17:35 EDT. All 15 cthompson guests,
the domain, SQL, primary installation, CAS expansion and passive installation
progressed without external intervention. The two selected OS updates installed
and restarted normally on PS1-PSS and PS1-LIB. Baseline primary setup succeeded
on its first attempt.

The run failed at passive readiness on October 28 at 22:09 EDT. Native HA stage
14 reported only substage 0xe000c, "Validating the site server", failed because
its initial site master key was not yet available. Stages 11–13 were complete.
failovermgr.log shows that same substage completed on its next native cycle,
about 60 seconds later, without any repair, service operation or status change.
The helper had already stopped the Ansible run on the first failed observation.

Run 001 is FAILED and is not unattended proof. Its frozen archive SHA256 is
ebff357a485ef2bda1fdf5867c317bdf45c6970459bc76874aa6b3a0e891ffed;
configuration SHA256 is
38312e6973157b72d16161c27acf7d9440fb67a7075dc880216ad2ef04250ae5.
Evidence, native failure/recovery history, exact inputs and source hashes remain
under .tmp/evidence/unattended/run-001. The lab is retained for diagnostic
resumption; any further deploy invocation will not qualify as a clean run.

A narrowly bounded five-minute grace is implemented for that specific native
validation substage after installation stages 11–13 complete. Other failures
still stop immediately. Persistent validation failure and the overall readiness
timeout still fail. Readiness continues to require completed native HA stages
and the expected installed version. No native key, queue or status is modified.
Regression validation passed 49 controller checks, 156 isolated PowerShell
helper checks, 11 isolated completion checks and eight PowerShell parses;
collection build, isolated installation and deployment syntax also passed. The
corrected collection was installed only for cthompson. A diagnostic resume through
normal user-defined roles started October 29 at 09:33 EDT; its evidence is in
.tmp/evidence/unattended/diagnostic-001. Finish diagnostic deployment, then repeat
a full clean rebuild from zero with frozen corrected automation. The owner's teardown
permission remains limited to user/range cthompson.

## Restart/resume implementation, October 28, 2026

The normal deployment now uses bounded phase checkpoints for native site, Windows
prerequisite, console and client restart requests. Only current-range Windows
inventory guests may restart, serially, after identity and native-state guards.
The coordinator exits before reboot and resumes from actual observed versions;
incomplete checkpoints never satisfy acceptance. Console 3010 requests use only
an automation-owned journal tied to the current boot.

Validation passed 47 Python/Ansible checks, 148 isolated PowerShell helper checks,
11 isolated completion-coordinator checks and parsing of eight PowerShell files.
The integrated live preflight passed; clean rebuild 001 failed as recorded above. Earlier assisted
evidence remains under .tmp/evidence/final and is not unattended proof.

## Unattended rebuild authorization, October 28, 2026

The owner explicitly authorized continuing development until an unattended clean
deployment is proven, including removal and redeployment of only user/range
cthompson. This supersedes earlier no-teardown language for this authorized test.
Every Ludus command must still include --user cthompson and range operations
--range cthompson. No other users, ranges or direct host files outside this
project may be accessed. No staging, commits, pushes or publication.

Integrate bounded native restart/resume handling, validate offline and against
isolated fixtures, install the exact source, then remove only the scoped range
VMs and run a full deployment. Preserve prior assisted evidence. A run requiring
an external recovery/restart/source correction is not proof of unattended
completion; fix its automation and repeat a clean run. Final acceptance requires
current hierarchy, passive server, remote roles, installed clients/consoles,
deployed boot images, native hotfix discovery and functional readback checks.

## Clean rebuild readiness, October 28, 2026

The completed host acceptance below verifies the resulting lab and its final
component reruns. This was an assisted deployment with targeted Ansible recovery,
restart and resume operations. The final source has not yet completed a new
clean deployment from zero without those interventions.

Known integration gap: native client restart requests stop completion, and console
restart requests stop the servicing role. The separate guarded client restart
play is not invoked automatically by the normal deployment. Integrate guarded
restart/resume handling and validate a clean rebuild before claiming unattended
end-to-end deployment. The current lab's installed-version and functional evidence
remains valid. No teardown is authorized by a readiness question.

## Completed host acceptance, October 27, 18:54 EDT

**The assisted deployment reached and passed the required lab end state.** The isolated cthompson
range was built from no lab through baseline 2509 to broadly available 2609.
CAS, PS1 and SEC are active at 5.00.9152.1000; passive PS1-PSV is ready at the
same release. SEC's native parent update status is 1. All 15 retained guests are
powered on and the scoped range state is SUCCESS. No range teardown occurred.

Twelve installed clients independently report 5.00.9152.1006, running and
assigned to PS1. The original snapshot missed CAS-PSS's October 23 native push
installation; client-scope-correction.json preserves that evidence. DC and SEC
remain unenrolled. SEC runs the MP-only agent from Program Files/SMS_CCM, which
is correctly distinguished from an installed SMS_Client. Both installed consoles
are 5.2609.1050.1000. SCP, provider, MP and DP binaries were independently checked
at build 9152. All seven site/storage role summaries are green; both MP-list
endpoints work. Replication has 86 ready groups.

Two accepted native hotfix scans found no applicable registered fix. Deployed
x64 boot image PS100002 was refreshed from source 2 to 3 and distribution
completed. The undistributed ARM64 image was preserved. The final verification
rerun reported Complete=true, Changed=false, no failures and no unreachable
endpoints, reusing the successful boot-image journal without another reload.

Functional acceptance passed: MP HTTP 200, a 512-byte PXE/TFTP boot-loader block
(no OS deployment), and strictly newer DEV hardware inventory received on PS1.
The client provider returned null for native schedule return values through both
CIM and WMI. The check records those as unknown, never as code zero; actual new
server-side inventory is the proof. Fresh post-recovery CM_SEC CHECKDB returned
zero consistency errors with no repair. Four native client restart requests
(MONITOR, CAS-DB, PS1-DB, PS1-DP) were completed normally through the saved serial
Ansible play. No SQL service/process was manually forced or stopped in this stage.

Source fixes include storage/MP readiness, authoritative production client
versions, COM output suppression, local helper self-copy avoidance, process-only
remote execution policy, installed-client class detection, service/assignment/
setup/reboot checks, coordinator-log preservation and plain console-version JSON.
119 isolated PowerShell checks, seven-file parsing, three live client-classification
checks, earlier 43 Python checks, collection build/isolated install and Ansible
syntax passed. Final guest helper/script SHA256 values match repository source.
The collection is installed only for cthompson; archive SHA256:
35b5368a96411ad6ac89f2e93a442df4d5b132d041d258e05c287f78a34f89e9.

The full .tmp/cthompson-latest.yml config is restored and API readback matches
it exactly (SHA256 73b41612e5a76ab2c9b9a42ff327253dbcab30ce14eb778e65fd308e9a89a362).
Temporary operational roles are unassigned. Only SEC VM 189 was recreated earlier;
its retained UUID is 54E17E65-CCB7-4E8B-80D8-5A8016AF8BE1. The branch remains
test/sccm-version-selection. Nothing was staged, committed, pushed or published.
Existing research-lab upgrades and other fresh topologies were outside this run.

Review .tmp/evidence/final/acceptance-summary.json, report-acceptance.json,
client-readiness.json and cas-pss/deployment-report.json. Supporting evidence is
in final-new-inventory.log, final-mp-http.log, final-pxe-tftp.log,
final-automation-artifacts.log, pending-client-restarts-apply.log,
secondary-post-recovery-checkdb.log, secondary-native-up-to-date.json,
completed-catalog-checkpoint.log and remote-role-builds.json. Preserve these
records; do not repeat recovery, destroy/create or restart plays without new need.

Only user/range cthompson is authorized, with explicit --user on every Ludus
command. Direct host files stay inside this project. No other users/ranges,
range teardown, forced SQL termination, managed queue/identity/status edits,
OpenHound or ConfigManBearPig changes. User-facing times use EDT. Guest raw UTC
is host UTC+4h; do not change clocks. All deployment changes used Ludus/Ansible
and their automation is saved. Historical pending notes below are superseded by
this completed checkpoint.

Earlier incident disclosure remains required: automatic review rejected forced
SQL termination for corruption/data-loss risk, but an intended WhatIf preview
unintentionally killed old SEC SQL PID 2852 because win_powershell replaced its
common parameter from check mode. This was disclosed and apologized for; later
master/model/msdb/CM_SEC integrity checks were clean and that old guest was
subsequently recreated. No repeat or further force approval exists. Corrected
helpers use an explicit Preview early return.

## Agreed outcome

Update this Ansible collection so a fresh Ludus deployment finishes on the requested SCCM release. Also provide a supported route for upgrading the existing mayyhem.com research lab. Preserve its hierarchy and intentional research settings where the selected Microsoft release permits them.

The user-facing settings will be:

```yaml
ludus_sccm_target_version: "latest"
ludus_sccm_install_hotfixes: true
```

An explicit release, such as `"2509"`, means stop at that release. `"latest"` means automatically choose the newest broadly available current-branch release, excluding technical previews and early-release opt-ins. Resolve and record the target once for each deployment so it cannot change halfway through. A later deployment can select a newer release.

The hotfix switch defaults to true and includes applicable SCCM hotfixes for the selected release. False skips additional hotfixes. It never uninstalls fixes already present. Selecting an older release or earlier patch level on an existing installation must explain that a fresh lab is required, rather than automatically removing or rebuilding anything. Fixes already included in installation media cannot be removed by this switch.

Completion includes CAS, PS1, SEC, the passive site server, remote roles, installed consoles, and reachable lab clients. Update and redistribute the boot images used by the lab. List unreachable or incomplete systems explicitly. Match each component against its expected version; console and client version numbers need not equal the site version number.

## Working boundaries

### Ludus-host test authorization, 2026-10-23

- Test a fresh isolated deployment belonging to Ludus user `cthompson` on this
  host. Every Ludus command must explicitly include `--user cthompson`.
- Do not access another user or range. Keep source changes, local inspection,
  validation files, artifacts, and retained evidence inside
  `/home/cthompson/ludus_sccm`; do not inspect files elsewhere on the host.
- The authorized range is ID `cthompson`, number 1, with guest networks
  `10.1.10.0/24` and `10.1.11.0/24`. These supersede the old research lab's
  addresses for this run. Confirm guest membership from the scoped range API.
- Acceptance for this host run is end to end: start with no lab and finish with
  the current broadly available SCCM release installed across the requested
  hierarchy and components. Resolve `latest` again and enable applicable fixes.
- Guest restarts and redeploys are authorized at any time. Destroying the range
  or starting over by tearing it down requires the owner's explicit permission.
- The owner waived a pre-existing coordinated recovery point for this fresh
  range. Keep the implementation's normal site/database recovery checks.
- Begin with controller/offline validation and artifact verification. Historical
  fresh-install variants and the existing 2403 research hierarchy are outside
  this run's acceptance scope; do not access that existing hierarchy.
- Do not stage, commit, push, publish, or change unrelated projects.

- Work in `C:\Users\domainadmin\ludus_sccm`. Do not change OpenHound or its shared libraries.
- Do not stage, commit, push, create a release, or publish the collection. The owner will review and perform Git actions.
- Implementing the collection does not itself authorize starting an upgrade, restarting guests, or rebuilding the running lab during this development pass. Preserve it for the owner's branch testing.
- Active tests may target only 10.10.10.0/24, 10.10.11.0/24, and mayyhem.com objects reached through authorized hosts. Validate DNS results before remote access.
- Use existing Ansible and PowerShell facilities where practical. Add no new runtime dependency without checking its license and documenting why it is needed. This collection already declares GPL-3.0-or-later; do not copy its implementation into the Apache-licensed collector.
- Keep comments and documentation in plain English. New tests belong under `tests/`.
- Supporting-software policy: retain existing Windows and SQL major versions where practical; change prerequisites needed for compatibility and support. A general Windows/SQL modernization is not an agreed goal.

## Evidence from the existing lab

Read-only inspection on 2026-10-21 found:

| Component | Observed state | Consequence |
| --- | --- | --- |
| CAS, PS1, SEC | SCCM 2403, 5.00.9128.1000 | An intermediate release is needed before the then-current broadly available target, 2603. |
| CAS-DB and PS1-DB | SQL Server 2022 Developer RTM, 16.0.1000.6 | Review supported SQL updates. |
| CM_CAS and CM_PS1 | Compatibility level 160 | Use supported level 150 while on releases before 2603; verify behavior before and after the change. |
| PS1-SEC | SQL Server 2016 Express SP2, 13.0.5026.0 | Plan SP3 before an in-place SQL Server 2022 Express upgrade. |
| SCCM software inventory | ADK 10.1.25398.1 with WinPE add-on 10.1.22621.5337 | Recheck installed versions directly, then replace with a supported combination. |
| SQL connection drivers | Mixed 18.1.2.1 and 18.5.2.1 | Some hosts need newer drivers; the existing unconditional 18.5.2 pin cannot serve all future targets. |
| Inspected site servers | Windows Server 2022, .NET Framework 4.8 | No general server OS replacement is proposed. |
| CAS update catalog | Includes 2509 but not 2603 | The newest visible package is not necessarily the final reachable release; refresh after intermediate upgrades. |

At that inspection, Microsoft described 2603 as globally available and 2609 as early release. These are dated observations, not permanent defaults. The proposed existing-lab route was 2403 -> 2509 -> 2603. Microsoft's evaluation download advertised 2509, giving a proposed fresh route of 2509 -> 2603. Revalidate availability and requirements before a live run.

## Design and alternatives

### Release selection and upgrade paths

Keep a small central list of understood releases with their build numbers, available baseline media, prerequisite requirements, and allowed source versions. Resolve explicit requests against that list. For `latest`, establish Microsoft's broadly available release independently of the packages currently applicable to an older site. Do not treat a release date, the largest build number, or presence in an opted-in early catalog as proof of broad availability.

Use Microsoft's published release/checklist information and the site's normal servicing catalog, with a documented source contract and tests. If those sources disagree or cannot establish broad availability, stop with an actionable message. Do not silently choose an older release. A newly published release with requirements the collection does not understand must also stop clearly; automatic release discovery does not eliminate maintenance of compatibility rules.

Choose installation media separately from the final target. Fresh installations use a supported baseline and then the necessary updates. CAS expansion must use media compatible with the primary site being expanded. Do not run release upgrades concurrently with CAS expansion or creation of other site roles.

Existing deployments compare the requested build with actual site builds. Same release means verify and finish requested fixes; older means plan the supported upgrade route; newer means reject a downgrade. A mixed-version hierarchy requires checking update progress rather than blindly starting another update. Readiness and recovery checks must distinguish an update in progress, a failure, and a completed installation.

A single hardcoded newest release was rejected because the owner wants automatic broad-release selection. An unrestricted newest-version lookup was rejected because early releases and incompatible prerequisites must be excluded. Reinstalling SCCM to change versions was rejected because it would destroy research state.

### Prerequisites and cached installers

Make prerequisite decisions depend on the starting release, each intermediate release, and the final target. Review SQL engine support, database compatibility level, .NET, ADK/WinPE, ODBC, Visual C++ runtimes, Windows support, disk space, and pending restarts on applicable hosts.

Use supported ADK/WinPE components, not simply the newest downloads. Microsoft currently identifies ODBC 18.6.1.1 as problematic and 18.7.1.1 as incompatible with SCCM 2603 and earlier. Do not generalize that every version after 18.6.1 is broken. Confirm exact requirements and installer signatures before use.

Installer cache names and extraction directories must distinguish media versions. Check the installed version and downloaded content, not just whether a file exists. Replace misleading 2303 filenames used for 2403 downloads. Keep advanced installer URL/checksum overrides documented and validate that the supplied media matches the planned release.

For the existing secondary SQL instance, plan an SP3 update before SQL Server 2022 Express. Follow Microsoft's SQL upgrade procedure and verify the secondary database and replication afterward. Do not assume an SCCM update upgrades an existing SQL instance just because its new-site installation media contains a newer Express installer.

### One final hierarchy update role

Add one coordinating role at the top-level site after all required installation roles have really finished. Wire its prerequisites in `new-config.yml` so CAS expansion, provider installation, passive-server installation, and secondary-site creation cannot race it. Also document standalone-primary usage without assuming that CAS, a passive server, or SEC exists.

For each release hop:

1. Verify health, required backups/recovery arrangements, and prerequisite checks. Record maintenance settings before temporary changes.
2. Refresh the servicing catalog, obtain the intended package, and wait for download completion.
3. Start the update at CAS (or the standalone primary), using Microsoft's supported management commands.
4. Wait for the primary sites, passive servers, and affected remote roles to finish. Verify actual builds and readiness.
5. Initiate each secondary-site upgrade after its parent finishes and wait for completion.
6. Verify replication before starting another release hop.

Handle long-running work with bounded waits, progress messages, and useful failure evidence. A timeout must report the affected site, current stage, and relevant log locations. On a rerun, inspect current state and continue safely. Never route an existing-site upgrade through the fresh-install retry/uninstall logic.

Use one resolved target throughout the run. Never start concurrent hierarchy updates from every site server.

### Actual completion, fixes, consoles, clients, and boot images

Correct the secondary and passive installation roles, which currently write SUCCESS after submitting the installation request. Site presence and a running SMS_EXECUTIVE service do not establish installation success, requested version, or readiness.

When requested, select applicable updates for the chosen release, account for superseded packages and required installation order, and refresh after each installed fix. Use applicability rather than assuming that every KB listed online belongs on every lab.

Update installed consoles using the corresponding site's supported console installer. Upgrade reachable clients and verify their expected versions. Record failures and unreachable devices rather than silently omitting them. Refresh and redistribute used boot images and verify distribution completion.

Preserve intentional lab settings. Microsoft's security changes may remove older research behavior: 2603 changes access to Network Access Account information. Document changed behavior and compare collector results rather than treating every changed graph count as a collector failure.

## Delivery order and progress

- [x] Inspect the repository and existing lab read-only; agree on release selection, hotfix switch, full completion scope, and installation-check fixes.
- [x] Save this complete plan in the repository.
- [x] Implement and test the release-selection and upgrade-path foundation (36 offline tests and a live Microsoft document read; actual Ansible execution remains pending on Linux).
- [x] Connect selected baseline media and version-aware prerequisite/cache handling to installation roles (implementation; host validation pending).
- [x] Correct secondary and passive installation completion checks (implementation and offline behavior checks).
- [x] Implement and wire the final hierarchy update role, including state-aware reruns (live rerun validation pending).
- [x] Write applicable hotfix, console, client, boot-image, and final-report operations (live validation pending).
- [x] Update README and development/upgrade instructions; add review evidence and proposed Git commands.
- [x] Validate the resulting assisted cthompson deployment and component reruns (2509 -> 2609, October 27).
- [ ] Validate the final source in a clean deployment from zero with required restart/resume handling integrated into the normal flow.
- [ ] Validate the existing-lab upgrade after recovery arrangements and the live execution window are agreed.

Update this progress section and the implementation notes as work proceeds. Do not mark live validation complete based on offline checks.

### First implementation checkpoint, 2026-10-21

The read-only planner, optional `plan_sccm_version` role, controller action,
CLI preview, focused tests, and implementation guide now exist. See
[docs/version-selection.md](docs/version-selection.md) for how they work,
limitations, exact verification commands, and the proposed owner review/commit
commands. The normal installation roles and `new-config.yml` have not been
switched to version selection. The hotfix policy is recorded but not applied.
No live lab mutation, staging, commit, or push has been performed.

### Host-test implementation checkpoint, 2026-10-22

The preparation/install roles and sample configuration now use version selection.
The root servicing role and Windows helpers are written, including component
updates, real secondary/passive completion checks, recovery material, and JSON
reporting. Local checks passed: 40 Python tests, 22 PowerShell behavior checks,
YAML/module-help and PowerShell parsing, focused Python checks, and whitespace
checks. These are offline checks, not evidence of a completed lab upgrade.

No Linux controller was available. At the owner's request, the next agent has
a [Ludus-host handoff](docs/LUDUS_HOST_HANDOFF.md) with build, Ansible checks,
artifact installation, test cases, concrete uncertainties and recovery evidence.
In particular, media extraction, multi-role target sharing in Ludus, vendor
installer behavior and live component servicing need host testing. No lab
upgrade, Git staging, commit or push was performed.

### Ludus-controller validation checkpoint, 2026-10-23

The owner authorized the fresh `cthompson` range only, with `latest` and
additional hotfixes enabled. The selected range was `DESTROYED` with zero VMs.
Its full configuration, copied from `new-config.yml` to
`.tmp/cthompson-latest.yml`, was accepted by Ludus before deployment.

Controller checks now pass on Linux: 40 Python unit tests, 68 parsed YAML
documents and module help, collection build and isolated installation, installed
module documentation, planner syntax and execution in normal/check mode, and
deployment-role syntax. The required scripts, helpers, tasks, defaults, and docs
are present in the archive. The controller exposes Ansible core 2.16.18 with
Python 3.13.5; offline checks passed on that pairing, but it does not establish
support for every controller module. Ludus reports client/server
2.3.2+bba3dd3a. Its user-scoped collection list includes ansible.windows 2.7.0,
community.windows 2.3.0, and microsoft.ad 1.8.0. uv, Ruff, ty, and PowerShell are
unavailable here; their previously recorded Windows checks were not repeated.

A fresh Microsoft Learn read resolves `latest` to 2603, excludes early-release
2609, and selects the fresh route 2509 -> 2603. Evidence and the artifact
checksum are retained under `.tmp/evidence/` inside the repository.

Ludus installation was initially blocked by permissions in the existing user-scoped
`mayyhem.ludus_sccm` collection directory. Both replacement and removal through
`ludus --user cthompson` return permission denied; removal specifically names
`MANIFEST.json`. The owner manually repaired the collection permissions.
Installation through `ludus --user cthompson` then succeeded without sudo or
direct file access outside the repository.

This server treats a collection archive URL as Git, despite the CLI help. A
repository-local archive path is not accessible to the server. Local source
upload also failed to register the collection. Serving a bare copy of the
existing test commit over loopback successfully fetched commit
`251334f0b585e9ee94e8136a6b624bed01a17732`, then encountered the permission
failure above. After the owner's repair, the same pinned Git-source installation
succeeded. The temporary HTTP servers have been stopped. No staging, commits,
pushes, or range destruction were performed.

The full fresh deployment started in range `cthompson` on October 23 after
successful collection installation. Initial pre-run checks passed and Ludus is
provisioning the router and guests. Live acceptance remains pending; monitor
this deployment rather than starting another one or tearing down the range.

All 15 VMs (14 Windows guests plus router) are now provisioned at their configured
addresses. Read-only preflight on CAS-PSS, PS1-PSS, PS1-SEC, CAS-DB, and PS1-DB
found 250 GB system disks, approximately 239 GB free, and no pending restart
before domain creation. Sysprep logged temporary WinRM disconnects during
reboots; Ludus's existing retry handling recovered them and continued. The
workstation also completed Windows setup and hostname restoration after a
longer retry. The fresh domain was created; a read-only check confirmed DC is
joined to `mayyhem.com`, has no pending restart, and is accepting DNS, LDAP,
WinRM, and AD Web Services connections.

The first attempt later marked PS1-DB unreachable during the framework's
Windows/BGInfo setup: creating an Ansible temporary directory returned exit 1
despite printing its created path. A direct read-only recheck of that same guest
then succeeded with no changes. The current play had already excluded the
guest, so the agent aborted only that Ansible process and started a full
deployment rerun, as authorized. All 15 VMs and the new domain were retained;
the range was not torn down.

That second attempt then stopped in the framework's custom router DNS-rewrite
task with `free(): invalid pointer` followed by `ERROR! A worker was found in a
dead state` (Ludus log ID `pm4t6h7yim0j1ku`). It had not reached the SCCM roles.
A third full attempt, with Ansible diagnostics enabled, passed that same
DNS-rewrite stage and the earlier PS1-DB BGInfo error. It then attempted to use
the inherited shared Chocolatey/Nexus repository at `192.0.2.2:8081`, outside
the authorized range. The agent stopped the Ansible process on seeing that
dependency; no manual access to that repository or another range was made.

The test copy now omits the optional SystemInformer and SQL Server Management
Studio Chocolatey requests and their checksum switches. The original
`new-config.yml` is unchanged. Required SQL/SCCM/prerequisite installers do not
use Chocolatey, and all shared version settings and role dependencies remain.
The modified configuration was accepted by Ludus, and a fourth full attempt is
running with the same 15 guests and domain. Only filtered task/error summaries
are kept in the repository. No host runtime files have been inspected or
changed, and no collection-code changes have been needed yet. SCCM installation
remains pending.

The fourth attempt reached the collection roles after domain joins. All 14
Windows DNS names were verified against their expected `cthompson` addresses.
DC base preparation and ADCS completed, and other base roles were progressing.
An unexpected Ludus host reboot then interrupted the deployment near PS1-DB's
base-role completion marker. After the owner requested resumption, the range
reported `ABORTED` with all 15 existing VMs powered off. The agent started a
full deployment again to power on and resume those guests; no teardown or new
range was requested. The test configuration still excludes optional Chocolatey
packages that depended on the out-of-scope shared Nexus server.

The scoped `range inventory` response also included shared infrastructure.
The saved inventory was filtered to the 15 `cthompson-*` guests before any
direct guest validation; never use an unfiltered inventory for this run.

After resumption, DNS verification again passed for all 14 Windows hosts.
Version-aware SQL-driver preparation and SQL Server setup completed on the
site-database hosts, and the monitor's configured SQL role completed. Remaining
site-system and site-server prerequisites are progressing; no site installation
or final servicing result has been claimed.

A standalone read-only SQL check lacked the framework's domain-account
variables. An attempted adjustment to read autologon credentials was rejected
by automatic approval review because that source was not specifically
authorized; it did not run and was removed. Instead, the temporary user-local
role `ludus_sccm_host_validation` is installed through Ludus and uses only the
normal provisioning variables already supplied to collection roles. Execute
that read-only verification after the main deployment, within Ludus's role
context; do not retrieve guest credentials or run the standalone play without
the required configuration context.

The resumed deployment completed SQL setup on CAS-DB, PS1-DB, and the monitor,
then reached baseline extraction on PS1-PSS. The downloaded, Microsoft-signed
2509 executable identifies itself as a 7-Zip SFX archive. The legacy `/s -d`
switches left its process idle with no files extracted. Only Ansible was
aborted; the range and installed prerequisites were retained. The extraction
task now selects `-y -o"<directory>"` for this format, preserves legacy switches
for older media, accepts only exit zero, and bounds extraction to 30 minutes.
A completion marker is written only after setup's signature/build checks pass,
so an interrupted extraction is retried. No extraction dependency was added.

Validation of that fix: 40 Python tests, 68 YAML/help documents, isolated
collection build/install, and both Ansible integration syntax checks passed.
Windows PowerShell parsed 61 files and passed 27 offline behavior checks,
including format selection, destinations containing spaces, timeout process
cleanup, and unsuccessful exit codes. Actual extraction on PS1-PSS then passed
with Microsoft-signed setup version `5.0.9141.1002`. The new archive has
`SMSSETUP` at its root, so its output destination includes `cd.retail.LN` to
preserve the existing shared media path; legacy archives supply that folder
themselves. Both format fixes were uploaded and installed for `cthompson`.

Deployment resumes with `--tags user-defined-roles`, retaining the completed
VM/domain provisioning and all guests. The test configuration additionally
attaches the temporary read-only SQL verification role to CAS-DB and PS1-DB,
after each database installation. End-to-end site/servicing acceptance remains
pending.

Uncommitted collection changes can be uploaded using Ludus's source interface.
This server's source registration rejects collection-only bundles, but accepts
a bundle containing the collection and an empty, unselected metadata role.
Source `cthompson-sccm-fixed-test` contains both; only `mayyhem.ludus_sccm` was
selected and installed, scoped to user `cthompson`. The metadata role remains
uninstalled. This avoids sudo, commits, and direct access to runtime host files.
Use `source update` and then a forced selected collection install for subsequent
local builds; never apply a blueprint or use `--global` for this test.

The embedded 7-Zip extractor's supported `-y` and `-o` handling is documented in
its [upstream source](https://github.com/ip7z/7zip/blob/main/CPP/7zip/Bundles/SFXWin/SfxWin.cpp).

The resumed role run passed actual extraction on CAS-PSS and reused PS1-PSS's
verified media unchanged. A separate second extraction run also reported zero
changes. CAS-DB's read-only SQL check confirmed SQL 2022 Developer
`16.0.1000.6`, ODBC `18.6.2.1`, a running engine, and model compatibility 150.
At approximately 18:25 UTC, PS1's first site setup attempt started after its
pre-install restart and successful SQL connectivity probe. Setup is downloading
and verifying Microsoft prerequisites; no prerequisite error/warning entries
were present at the first read-only progress check. This is progress, not a
completed site or end-to-end acceptance result.

PS1's first setup reached the vendor's OLE DB 19.3.5 prerequisite and failed
with MSI 1603. The Application log explicitly required Visual C++ 2022 x64 and
x86 at least 14.34; only x64 14.44 was installed. Ansible was stopped before its
automatic reinstall path. Both runtime architectures are now downloaded,
checked against the signed installer's version independently of ODBC, and
verified from their software version registry keys after installation. Newer
installed runtimes are retained. The existing ODBC check no longer skips this
independent prerequisite when its own version is already current.

Validation passed 40 Python tests, 31 offline Windows PowerShell behavior checks,
61 PowerShell parses, YAML checks, collection build/install, deployment syntax,
and planner execution in normal/check modes. The live PS1 repair then installed
x86 14.44.35211.0 and successfully installed the exact previously failing OLE
DB 19.3.5 MSI. No site Full Version registry value or SMS_EXECUTIVE service
existed, so no installed site was removed. Only the identified failed setup GUI
was stopped. The guest restarted successfully, the updated collection was
installed user-locally through the same source interface, and role deployment
resumed at about 18:35 UTC. End-to-end acceptance is still pending.

The first setup also logged SQL mixed-authentication and minimum-memory
warnings. Mixed authentication is used by the configured research roles.
Record and review these when servicing prerequisites run; do not claim those
warnings were resolved by the unrelated runtime fix.

Microsoft documents the dual-architecture prerequisite in
[Installing OLE DB Driver](https://learn.microsoft.com/en-us/sql/connect/oledb/applications/installing-oledb-driver-for-sql-server?view=sql-server-ver17).

The resumed PS1 setup started around 18:46 UTC, passed the repaired prerequisite,
created `CM_PS1`, and imported the initial software lookup data. During the
long import, a read-only SQL guest sample confirmed active CPU usage/database
log writes and about 1.9 GB of free memory. By 18:58 UTC, setup had advanced to
database keys/indexes. Its Full Version registry value is now
`5.00.9141.1000`, but SMS_EXECUTIVE and the completed-setup marker were not yet
present at that checkpoint. Preserve this in-progress site and let setup finish;
the registry value alone is not acceptance. The intended install stall timeout
is 30 minutes in the test configuration. No timeout or healthy-state guard was
bypassed to accommodate the import.

At about 19:08 UTC, PS1 baseline setup and console verification completed and
post-install account/GPO configuration began. Its SMS Executive service is
running. The initially absent push GPO was created/imported/linked successfully;
the expected missing-GPO probe is ignored. The run then stopped at remote
`Invoke-GPUpdate` with Access Denied. The installed site was retained.

The policy module now refreshes computer policy locally on its calling computer
and uses existing WinRM for remote computers, avoiding remote scheduled-task
activation. It returns per-target results, reports the computer on failure, and
honors check mode without changing policy. Offline helper tests and parsing
passed. A temporary role `cthompson_policy_validation` is testing the module in
the normal Ludus domain-account context: first list targets in check mode and
require exactly the 13 authorized member computers, then run the refresh.
The test uses `.tmp/cthompson-policy-test.yml` and only that role. Restore
`.tmp/cthompson-latest.yml` before resuming all collection roles; do not claim
policy refresh or the remaining hierarchy is complete before the test passes.

The isolated policy validation completed successfully around 19:17 UTC. Check
mode listed exactly the 13 intended member computers without changes; the
actual refresh then returned exit zero for all 13. Evidence is saved in
`.tmp/evidence/policy-refresh.json`. The temporary policy-test config was
replaced by `.tmp/cthompson-latest.yml`, and all collection roles resumed.
The policy validation role is no longer attached to the active config. Windows
validation now passes 34 behavior checks and parsing of 62 files. The installed
PS1 site must be preserved; remaining hierarchy/servicing acceptance is pending.

The owner clarified that deployment changes must use Ludus/Ansible and fixes
must be encoded in the automation. Temporary Ansible plays are for diagnosis
and validation; they must not become undocumented prerequisites for a fresh
deployment. Extraction, runtime preparation, and policy-refresh repairs are in
the tracked collection code and installed for this user.

The next main run passed policy refresh and discovery/boundaries, then stopped
because the default Windows 11 PXE ISO was absent from the shared controller
store. No manual inspection or change of that store was made. The primary-site
role now optionally downloads the ISO on the guest using
`ludus_sccm_pxe_iso_url` and mandatory `ludus_sccm_pxe_iso_checksum` (SHA-256).
The existing controller-file mode remains available with an empty URL. The role
stops if a changed ISO would silently reuse an existing cached WIM. README
documents the settings.

The test configuration uses Microsoft's official Windows 11 Enterprise LTSC
2024 x64 evaluation image, matching the supported ADK 26100 platform:

```yaml
ludus_sccm_pxe_iso_url: https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso
ludus_sccm_pxe_iso_checksum: 67cec5865eaa037a72ddc633a717a10a2bed50778862267223ddb9c60ef5da68
```

The URL was resolved from Microsoft's Evaluation Center; the checksum was
calculated from that official HTTPS download and pinned for reproducibility.
The current linked publisher verification page covers 26H2, so no claim is made
that an independently retrieved LTSC publisher checksum document was verified.
The tracked acquisition tasks downloaded 5,112,850,432 bytes on PS1, verified
that exact checksum, and reused the file with zero changes on a second run.
Build/YAML/syntax checks passed, the updated collection was installed through
the same user-scoped source interface, and the main configuration was accepted
with these settings before deployment resumed. The guest was not manually
seeded with an ISO outside those automation tasks. Evidence is in
`.tmp/evidence/pxe-media-acquisition.log`, `pxe-media-rerun.log`, and
`windows-iso-source.json`. Hierarchy/servicing acceptance remains pending.

At approximately 19:50-19:51 UTC, the main Ludus role verified the configured ISO,
copied the WIM, added/distributed the OS and boot-image content, and created the
Deploy-OS task sequence. PS1 post-install configuration passed. CAS-PSS then
started its first fresh setup attempt around 19:52 UTC, after its reboot and
successful SQL probe. Preserve PS1 while CAS setup completes. CAS has not had
the temporary PS1 OLE DB repair play applied; its setup exercises the runtime
prerequisite fix through normal collection preparation and vendor setup.

CAS passed its first setup/console checks around 20:20 UTC, and Ludus advanced
to the remaining site-system prerequisites. A read-only check during CAS setup
confirmed both Visual C++ runtimes at `14.44.35211.0` and OLE DB `19.3.5.0`,
installed by the normal collection/vendor path without the PS1 repair play.
CAS and PS1 component services are running; RCM reports the CAS/PS1 expansion
link completed. USMT scanstate/loadstate files exist on both sites. Preserve
both installed sites while subsequent roles continue.

The current read-only client preview reaches all 14 Windows guests. Eleven
have a running client at `5.00.9141.1011` and report site PS1. DC has no client
(the default configuration disables DC client push), and CAS-PSS/PS1-SEC have
no client at this checkpoint while hierarchy work is still in progress. This
is a baseline preview, not final client-version or acceptance evidence. Logs:
`.tmp/evidence/client-readiness.log`, `cas-setup-progress.log`, and
`expansion-diagnostics.log`.

At 20:38 UTC, the passive server's vendor setup log records completion and
both site component services are running at baseline `5.00.9141.1000`.
The active server is still bootstrapping passive components; the collection's
HA-stage readiness check continues. This is installation progress, not proof
that passive readiness or the selected-release acceptance has passed. Read-only
Ansible evidence is in `.tmp/evidence/passive-progress.log`.

The passive readiness check was paused around 20:48 UTC for read-only Ludus
diagnostics. Both CAS/PS1 are active at `5.00.9141.1000`; all 86 reported
replication groups have initialization status 6 and zero failed/degraded syncs.
HA stages 11–13 completed, but stage 14 reports failure (3). The detailed
monitor names `Validating access to remote site systems`; passive
`failovermgr.log` records access denied (0x5) to `ps1-mp.mayyhem.com\ADMIN$`.
The local diagnostic account cannot see provider rows, so its empty results
were not treated as evidence about HA. The provider evidence came from a
temporary read-only Ludus role using the usual domain provisioning variables.
No credential lookup or permission bypass was used.

The sample's MP/DP/SMS passive-admin tasks already existed, but passive
installation did not depend on them. They had not executed when its readiness
wait began. PS1-DB lacked an equivalent local-admin assignment. The proposed
`new-config.yml` and `.tmp/cthompson-latest.yml` now add the DB assignment and
make passive installation depend on all six relevant admin tasks. Both full
role graphs are acyclic with valid references. Existing PS1-LIB and PS1-PSS
memberships were verified; only PS1-DB, PS1-DP, PS1-MP and PS1-SMS need new
`MAYYHEM\PS1-PSV$` local-Administrators memberships. The shared readiness helper
now stops on a failed HA stage and names its failed substep/log rather than
waiting for the timeout. Thirty-six mocked Windows PowerShell behavior checks,
62 parser checks, YAML validation, collection build/isolated install and both
integration syntax checks pass.

Automatic approval review rejected the permission application because the four
account/host grants require explicit authorization. No grant was executed.
Keep deployment paused pending that approval. It also rejected a proposed
temporary diagnostic config that would clear other role assignments; that
proposal was not executed. The safer diagnostic retained every existing role
and used `--only-roles`. Diagnostic runs reported SUCCESS, which is not a
complete deployment result. Evidence: `.tmp/evidence/passive-ha-detail.json`,
`passive-access-diagnostics.log`, `site-system-admins-before.log` and
`offline-windows-check.log`. Restore the main config and resume only after
the permission decision; never remove the installed sites or range.

### October 26 approved resumption

The owner explicitly approved the requested passive-account administrator
memberships. The corrected full config was accepted, and the normal Ludus
Ansible membership role applied the four additions. Read-only guest checks
verified them and the existing PS1-LIB/PS1-PSS memberships. The selected role
also applied the PS1-SEC passive-account assignment already present in the
original config. That fifth pending assignment had been missed in the earlier
four-host list; it was disclosed to the owner and recorded. No new account or
host outside this range was used. Passive installation now depends on all
seven configured site-system admin tasks; both config graphs are acyclic.

After restarting only passive SMS Executive through Ansible, its log reported
successful remote-site-system access. The normal provisioning-context provider
check confirms HA stages 11–14 completed (2), stage 15 remains unrequested (0),
CAS/PS1 are active at baseline `5.00.9141.1000`, and all 86 replication groups
are ready with zero failed/degraded syncs. All 15 guests are running and all
14 Windows DNS records were reverified. Evidence:
`.tmp/evidence/verified-passive-memberships.json`, `passive-revalidation-restart.log`,
`passive-access-after.log`, `passive-ha-after.json`, and `dns-preflight-resume.log`.
The main full configuration is being restored to resume remaining roles and
servicing. Earlier permission-pending notes are historical, not a current
authorization blocker. Full selected-release acceptance is still pending.

The full run subsequently passed passive readiness through the normal role
and advanced to PS1-SEC preparation. Policy refresh retained the approved
memberships; the existing PS1/CAS sites were preserved. Secondary Windows
features completed, and its prerequisite installation is in progress.

Secondary prerequisites completed and its installation was submitted. Parent
prerequisite checks then reported remote WMI access denied despite correct
machine-account administrator membership, working SMB, successful Kerberos
logons and normal WMI/DCOM descriptors. Restarting only SEC through Ansible
restored both `root\cimv2` and `root\WebAdministration` access under the primary's
SYSTEM/machine identity. The preparation role now restarts after Windows feature
changes, including when Windows reports no pending reboot. A direct run of the
updated tasks on the prepared guest passed with zero changes and skipped reboot;
YAML, integration syntax and whitespace checks pass. This source change still
needs installation before the next normal role run.

The secondary's first bootstrap attempt installed SQL 2022 Express successfully.
After the restart, bootstrap restarted setup. SQL instance discovery produced
repeated errors for a default `MSSQLSERVER` connection, although the actual
`CONFIGMGRSEC` instance was running on static port 1433. Read-only provider and
bootstrap inspection confirmed the original creation defaults already contain
ports 1433/4022; a tentative explicit-port code change was removed. No alias,
SQL port, registry, provider status or site-registration repair was applied.
Setup subsequently advanced and created `CM_SEC`, with baseline Full Version
present. Preserve this now-installed/in-progress site. Do not remove its
registration or restart fresh setup based solely on the parent's earlier
failed status while the guest installation is still progressing.

Evidence includes `secondary-wmi-default-after.log`, `secondary-reboot.log`,
`feature-restart-idempotence.log`, `secondary-provider-settings.json`,
`secondary-startup-sql-state.log`, `secondary-sql-databases.log` and
`secondary-setup-progress.log` under `.tmp/evidence/`. At the database-creation
checkpoint, `CM_SEC` and model have compatibility 160; verify the expected
compatibility through the normal servicing step before declaring acceptance.

SEC vendor setup completed around 20:12 UTC, with SMS Executive running at
`5.00.9141.1000`. The parent retained the earlier failed initial-request state;
setup logged that its completion message could not reach the bootstrap registry
entry that had been cleared during the interrupted monitor. A guarded temporary
Ansible role, using the normal Ludus provisioning context, verified the exact
SEC identity/version, running service and absence of setup/bootstrap processes,
then requested `SMS_Site.RequestedStatus=1001` (SEC_REQUEST_CREATE) through the
supported provider interface. This requests SCCM's retry processing; no Status
value was set and no site/database was removed. The request succeeded. Restore
the main config and resume remaining readiness/provider/servicing roles; verify
SCCM's own resulting status before claiming readiness. Evidence:
`.tmp/evidence/secondary-supported-retry.json`. The feature-restart automation
is installed in collection artifact SHA-256
`fe1f7ae585bb0c1242d06a6f86c6bf4b227c3278113764cdab15dcdcc444a971`.

### October 26 recovery and publishing checkpoint

The initial create retry correctly failed prerequisites on the already installed
secondary. A subsequent guarded `RequestedStatus=1011` request uses Microsoft's
[secondary recovery operation](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/recover-sites),
preserving the server identity and SQL instance while SCCM reinstalls files and
reinitializes data from PS1. The extra COPY_ONLY backup was verified but is not a
supported secondary recovery input. No read-only Status property was forced and
no registration/database/range was deleted. Inspect actual recovery processing
before any new request; running services alone do not satisfy parent readiness.

The System Management template previously granted only the executing server.
It now resolves the configured active, passive and secondary computer accounts
by exact DNS name and grants publishing Full Control only on that container and
its children, preserving other ACL entries. `-WhatIf` gates every directory
mutation; the live preview parsed and confirmed unchanged SDDL with exactly two
new targets (PS1-PSV and PS1-SEC). Automatic approval initially rejected those
security-sensitive additions; the owner explicitly approved the two grants on
October 26. Both grants were applied through the tracked template, verified, and the
second run left the ACL unchanged. Existing schema-admin membership was checked
before permission application. A separate final secondary-readiness task now enforces
site/model database compatibility at 150 when higher. Updated source passes
68-file YAML validation, both integration syntax checks, collection build and
isolated installation, 36 mocked Windows PowerShell checks and 63 parses.
The updated collection is installed for cthompson (SHA-256
`616b0ec37778faf4d1d6293764643075554b12f99da05a6035e6af11bb333f0e`).
The remote SMS Provider installation subsequently succeeded. Both providers
still report SEC failed; HMAN observed the generic 1011 write but restored the
old state without starting recovery. Read-only inspection of the installed
console's RecoverSecondarySite implementation shows it writes a pending request
and recovery operation into the site-control definition, enables prerequisites,
and saves through the management SDK. A guarded Ansible script now encodes that
operation and WhatIf preview; it preserves other embedded properties and never
assigns SMS_Site.Status. Its checks require the exact installed secondary, no
primary/secondary setup, running baseline service and the verified backup.
Automatic approval review rejected actual submission pending explicit approval
for SEC reinstallation/database reinitialization after the prior request failed.
The rejected command did not run. The separate preview-only role passed with
SDK Put gated by WhatIf and Submitted=false. It confirmed target, version,
running service, absent setup processes and existing backup. The owner then explicitly approved SEC recovery and continuation on October 26.
The guarded recovery, normal readiness and hierarchy servicing have resumed
with an added dependency ordering readiness after recovery; every original role
is retained. Servicing report output stays in this authorized workspace. Final selected-release
acceptance remains pending.

The approved recovery subsequently passed vendor prerequisites, created job
00000063, and entered native recovery-in-progress (Status 8). Bootstrap validated
and extracted its package, then launched RecoverSecondarySite. SQL waited during
single-user conversion with PRINT_ROLLBACK_PROGRESS while an old SMS component
remained connected. A guarded Ansible task verified that exact recovery state
and stopped only SEC's Site Component Manager/Executive, leaving SQL and setup
running. This quiescence is now encoded inside the operational recovery script's
ShouldProcess block before its SDK request. The old worker had already exited when a guarded process-stop task checked it;
no process was killed. SQL retained its sleeping old-worker session 110 with
zero open transactions. A separate guarded Ansible task closed that exact
orphan using standard SQL KILL, preserving the instance and active setup. The
operational recovery script now closes captured old-worker orphan connections
after bounded service/process shutdown and before its SDK request. No SCCM
application table or provider Status was edited. Native completion remains pending.

The disconnected old MARS session remained after KILL and the normal SQL
restart stalled in StopPending. Automatic approval rejected forced SQL process
termination. A supposed preview nevertheless terminated SQL PID 2852 because
win_powershell replaces a direct WhatIf argument with the Ansible check-mode
value. The owner was immediately informed. SQL restarted (PID 5488), completed
startup recovery, and native SEC setup advanced. No specific force approval was
received; do not repeat this action. The force automation now has an explicit
Preview return before mutations plus a separate false-by-default ForceApproved
gate. CHECKDB passed for master, model and msdb with zero consistency errors and no
repair. All three mocked preview/approval guard cases passed with zero mutation calls.
CM_SEC CHECKDB subsequently also passed with zero errors and no repair. The first
native recovery failed at 6:26 PM America/New_York: SQL interruption aborted its
database drop, then setup rejected the still-populated CM_SEC. Native setup
removed SCCM services; no setup or database user sessions remain. The Ansible
readiness wait was aborted with all 15 VMs retained. The guarded request now
accepts the failed-recovery partial service state only at parent Status 9 and
requires no remaining CM_SEC connections before resubmission. It contains no
forced process termination or SQL KILL. Native SCCM owns database replacement.
Parse validation and read-only terminal-state validation passed. The retry preview
returned Submitted=false, actual submission returned true, and native SCCM
successfully dropped CM_SEC at 6:40 PM America/New_York without a forced SQL
operation. Native reinstall and all servicing acceptance are still pending.
Technical cause:
[Ansible module source](https://github.com/ansible-collections/ansible.windows/blob/main/plugins/modules/win_powershell.ps1#L869).

### Broad target changed during the October 26 host test

The live Microsoft Learn Markdown endpoint announced 2609 broad availability on
October 26, while the cached web response still described early access. The
resolver correctly refused the newly broad release until its requirements were
reviewed; it did not fall back to 2603. The catalog now understands build 9152,
with upgrade floor 2503. Fresh route: 2509 -> 2609. An existing 2403 hierarchy
still requires an intermediate 2509 hop. The current isolated range already
meets the SQL 2017 CU2 minimum using SQL 2022; ADK 26100 and ODBC 18.6.2.1 remain
supported. Retain that ODBC version during the baseline; 18.7.1.1 blocks 2603 and
earlier. Native 2609 setup supplies updated OLE DB / Visual C++ dependencies.
Intentional research client-approval settings are preserved; resulting warnings
must be reviewed. 43 unit tests passed, including newly broad selection, retained
early-ring exclusion, baseline media and intermediate routes. Collection build /
isolated install, installed planner normal/check mode and deployment syntax
passed. The source is installed for cthompson; normal readiness and latest
servicing resumed without another recovery request. Live 2609 acceptance is
pending. The already submitted SEC recovery continues
independently; do not resubmit it due to the controller selection failure.

Baseline functional probes passed from PS1-DEV while native SEC recovery ran:
PS1-MP returned HTTP 200 and its expected management-point list; PS1-DP delivered
the first 512-byte TFTP block of SMSBoot/x64/wdsmgfw.efi, then the probe stopped
the transfer. No PXE boot or OS deployment started. Repeat these checks after
servicing; they do not prove a complete task-sequence deployment. Evidence:
`.tmp/evidence/baseline-mp-http.log` and `baseline-pxe-tftp.log`.

### Isolated SEC redeployment after the stalled native recovery

The retried native recovery recreated CM_SEC and its services, but PS1 never
created the Secondary_Site_Replication_Configuration initialization package.
A normal PS1 SMS Executive restart did not advance it. The installed replication
link analyzer returned NotApplicable with no rules or remediation. One guarded
SMS_ReplicationGroup.InitializeData call returned zero and replaced the tracking
GUID; the replacement again remained PendingCreation at 21 percent. These
results are not readiness or acceptance.

The owner previously authorized guest redeploys at any time. Recreate only
cthompson-ps1-sec (current VM 189, 10.1.11.200) and its SEC secondary registration.
Preserve CAS, PS1, the other 14 VMs and the range. Guard exact ownership before
VM deletion, gracefully stop SEC services and shut down the guest, and use the
supported Remove-CMSecondarySite Delete action for SEC metadata only. Reuse its
AD computer account where possible. Native SCCM owns all application database
changes. No forced SQL process termination is authorized.

Recreate SEC's declared Windows/domain prerequisites with Ludus. With the old
SEC registration removed, service CAS and PS1 to the recorded current broad
release, then create SEC from the updated parent's media and run final servicing
and validation for all three sites. A temporary two-site report is not final
acceptance. Individual guest recreation destroys SEC's local SQL/content;
parent sites, source automation and unrelated guests are preserved. No deletion
has been performed at the time this checkpoint was written.

The cthompson test config sets ludus_sccm_cache_directory to the project-local
.tmp/cache/sccm-downloads path for every VM. The role's default remains compatible
with existing installations. This avoids direct access to the shared host cache.

## Validation and acceptance

### Offline checks

Use focused tests under `tests/` for explicit/latest selection, early-release exclusion, malformed/unavailable release data, numeric build ordering, missing intermediate paths, downgrade rejection, and per-run target consistency. Test mixed-version/in-progress hierarchy handling, hotfix filtering, stale caches, prerequisite differences, and ready-vs-started installation states as those pieces are implemented.

Run PowerShell parsing and relevant PowerShell behavior checks on Windows. Use Ansible syntax/build checks on a supported Linux controller. Ansible is not installed on this workstation at plan creation; identify a suitable controller or an isolated Linux validation environment before claiming those checks passed. Do not change the collector's Python environment.

### Live checks

Before changes: record configuration and collector results; verify healthy file/database replication, backups and recovery files, free space, restart state, and installer access. Arrange a coordinated lab recovery point. Existing remote roles and clients must be included in the inventory.

Test fresh deployment at a historical supported target and at `latest`, both hotfix policies, and a second run of the same configuration. Exercise a failed/interrupted update without destroying the existing lab. Validate the existing 2403 hierarchy through its supported path separately. Confirm CAS expansion, passive readiness, SEC readiness, all expected site/role builds, replication, client policy and inventory, content delivery, console access, and boot-image distribution. Compare collector results and investigate unexplained losses.

A deployment passes only when requested components are ready at their expected versions. List unreachable clients separately. A reachable component that failed to update makes the result incomplete. A no-hotfix run must not apply optional fixes, and a rerun must not downgrade or reinstall working sites.

### Recovery

Preserve SCCM-supported site/database recovery material and customized files. Verify Proxmox access, backup storage, and a coordinated recovery procedure before live execution. Do not assume that reverting one database VM while the rest of a replicated hierarchy continues running is a valid rollback. Reverting an entire isolated research range is a lab operation requiring an agreed recovery point, including domain state where relevant. Preserve development files outside guest snapshots before restoring them.

## Documentation and review deliverables

README: new settings, placement in the Ludus configuration, supported release choices, fresh-vs-existing behavior, hotfix semantics, expected duration and internet requirements, and limitations. Provide examples using mayyhem.com without publishing credentials in test evidence.

Upgrade/development notes: problem, selected approach, alternatives, exact responsibilities of changed files, dependencies/licenses, downstream effects, test commands/results, manual verification, and known uncertainties. Document recovery and the distinction between submitted work and finished installation.

After implementation, recommend a concise commit message and exact staging/commit commands for the owner's review. Do not execute them. Do not push. The owner may use a new branch for live validation before merging.

## Authoritative references

- SCCM baseline and update versions: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/updates
- 2509 checklist: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2509
- 2603 checklist and broad availability: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2603
- 2609 checklist and broad availability: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2609?accept=text/markdown
- Evaluation media: https://www.microsoft.com/en-us/evalcenter/download-microsoft-endpoint-configuration-manager
- SQL support and compatibility levels: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-sql-server-versions
- SQL 2022 upgrade requirements: https://learn.microsoft.com/en-us/sql/database-engine/install-windows/supported-version-and-edition-upgrades-2022?view=sql-server-ver16
- Infrastructure upgrades: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/upgrade-on-premises-infrastructure
- ADK support: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-windows-adk
- Prerequisite checks and ODBC restrictions: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks
- Hierarchy update procedure: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/install-in-console-updates
- Passive-server servicing: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/configure/site-server-high-availability
- Backup material: https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/backup-and-recovery
- 2603 behavior changes: https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/changes/whats-new-in-version-2603
- Supported update management commands: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/install-cmsiteupdate?view=sccm-ps

SEC-only recreation checkpoint (October 27, 00:33 UTC): the first normal SMS
Executive stop timed out. A separate normal SQL service stop succeeded; no
forced SQL termination occurred. SEC then shut down normally. The supported
Remove-CMSecondarySite Delete action completed, retaining active CAS and PS1.
The exact VM ownership guard and all four negative mock cases passed. Only
powered-off cthompson-ps1-sec / VM 189 was destroyed through Ludus; the other
14 VMs, with unchanged IDs, addresses and power states, were verified intact.
The range was preserved. SEC's AD account SID/GUID was recorded and preserved;
no SEC publishing objects remained. The operational delete role is installed
preview-only and absent from the restored full config. Ludus vm-deploy and
DNS rewrite are now recreating the missing declared guest. Acceptance is pending.

The replacement SEC guest reused VM ID 189. Its Windows UUID is
54E17E65-CCB7-4E8B-80D8-5A8016AF8BE1. Ludus completed targeted Sysprep, static
address/hostname, Windows settings and domain join. Its built-in reconnect
handling recovered the expected Sysprep connection loss; final Windows/domain
provisioning passed. Independent Ansible checks confirmed SysprepSucceeded,
PS1-SEC.mayyhem.com, and the original AD computer SID/GUID. The one-time old-VM
deletion guard now rejects reuse, preventing deletion of the replacement ID.
A normal Invoke-CMSiteUpdateCheck was submitted at CAS with only CAS and PS1
registered and active. No early-ring opt-in or package-state change was made.
The SCP started extracting a new payload; applicability/version confirmation
and parent servicing remain pending. Only SEC's declared Windows base, admin
memberships and SCCM prerequisites are currently being applied. The active
config is again .tmp/cthompson-latest.yml with every original role retained.

The normal catalog check discovered a distinct applicable 2609 production package:
8b9745e4-b815-49d6-8faa-5fdc8b3df4fc, FullVersion 5.00.9152.1000, download state
262145. The older eeb7bd91 package at the same build remains not applicable and
is excluded by the coordinator. No early-ring enrollment was needed. Read-only
catalog evidence: .tmp/evidence/catalog-after-normal-sync.log. Servicing is
still pending while the replacement SEC completes declared prerequisites.

Direct-download correction: the Ludus Ansible worker cannot traverse/write the
project-local controller cache. No home-directory permissions were changed.
Added ludus_sccm_download_on_guest (default false) and set it true on every VM in
the cthompson test config. The optional controller cache path remains available;
in guest mode all controller download/copy tasks are skipped. Installers retain
the existing signature/build checks; literal algorithm:hex checksums are split
into win_get_url's algorithm/digest arguments, with malformed values rejected.
The new Windows integration test passed an official ODBC MSI download, Microsoft
signature check, unchanged SHA256 rerun and pre-transfer malformed-checksum
rejection. Build/install and deployment syntax passed. SEC preparation resumed
using only the updated collection; no new SCCM secondary has been submitted yet.
The primary computer account passed independent DCOM/WMI and ADMIN$ reads to
SEC after the feature-install reboot. Evidence: sec-parent-access-after-reboot.log
and guest-download-integration.log. Current installed artifact SHA256:
54096d3ed10a0f25b274a311a4d39088f8045c560552d04acbd3c53ce6be834a.
Active full config SHA256:
2c21a95173f3f2fcf58332d5a44503239401e4d3bb69a1f013710f6261514902.

At 00:57 UTC, replacement SEC prerequisite deployment passed (35 tasks, 6
changes, zero failed/unreachable). Native installer logs verified both Visual
C++ architectures, ODBC 18.6.2.1, ADK 10.1.26100.9457 and Windows PE. Full config
is restored with all original roles and direct guest downloads enabled. The
normal hierarchy-servicing role is now selected only on CAS-PSS to upgrade the
two retained active parent sites to 2609. SEC has no SCCM site registration yet;
create it from updated PS1 media after the parent stage succeeds, then run
three-site final acceptance. This intermediate stage is not completion.

Parent servicing preflight passed but the first release run stopped before update
submission: Copy-Item interpreted a UNC CD.Latest source using the current
CMSite provider and failed dynamic-parameter discovery. The CAS copy-only SQL
backup completed before that file-copy failure. Added Copy-SccmFile, which
explicitly selects the FileSystem provider for both source and destination.
Release/hotfix recovery copies, component media/helper transfers and secondary
SQL installer copies use it. Secondary UNC media probes are explicitly qualified
as well. A real CMSite integration test passed UNC-to-local, local-to-UNC and
UNC-to-UNC literal/wildcard copies, preserving file contents and the SCCM drive.
Seven PowerShell files parsed; the existing behavior suite passed. The first
isolated test attempt lacked its policy-module fixture; the completed fixture
bundle passed without production changes. Evidence: filesystem-regression-passed.log.
No release installer was submitted by the failed run. The tested source is now
being installed and normal parent servicing will retry with fresh verified
backups and CD.Latest copies. Evidence fetch from the Ludus worker also hit the
project-directory permission boundary; use the existing local Ansible fetch
fallback to retain reports inside this workspace rather than changing home
permissions. Neither issue requires a range or guest teardown.

The next parent run encountered the native console's 'Still checking for updates'
response because normal catalog synchronization was already active. Added a
shared Request-SccmCatalogCheck helper: only that known busy response continues
into catalog readiness waits; every other exception remains fatal. Hotfix rounds
that saw an existing active check do not count toward settled empty-catalog
acceptance. Three new mock cases passed (requested, already busy, other error),
bringing the PowerShell behavior suite to 39 checks. Seven-file parse and all
three live CMSite copy variants passed again. No release installation was
submitted by either failed parent run. Rebuild/install and normal retry follow.

### October 27, 01:54 UTC: native content-library sharing conflict

CAS00002 (the normal 2609 payload) transferred about 1.8 GiB successfully from
CAS to PS1. The update remains State 65537, content replication before actual
prerequisite execution; no release installer has been submitted. The first
PS1 despool attempt waited for package metadata, then subsequent attempts failed
on different temporary DataLib INI files. The preceding error is DeleteFile 32
(sharing violation); later rename errors 5/183 and 0x80070005 are secondary.
Do not interpret these alone as evidence to add permissions or reset packages.

Share and NTFS inspection showed PSS share Full Control and inherited SYSTEM /
Administrators Full Control. Both PSS$ and PSV$ are local Administrators on LIB.
Functional create, atomic replace, delete and WritePrivateProfileString tests
passed under both actual computer identities, before and after LIB restart.
Probe files were uniquely named and removed; managed content was preserved.
Defender is stopped on PSS and LIB. No ACL, account or antivirus setting changed.
A read-only SYSTEM observer with IncludeHidden captured 37 SMB-handle snapshots;
all library activity shown came from 10.1.11.50 as MAYYHEM\PS1-PSS$. Evidence:
content-library-retry-after-reboot-handles.json and the native despool logs.

The owner's existing any-time guest restart permission was used for a normal
LIB restart after guards confirmed content wait, zero local SQL services and
zero open content files. That did not resolve the next sharing failure. A
normal PSS restart is now running to clear client-side handles, guarded by the
same pre-install update state plus no local SQL or active setup processes.
The remote SQL host is not restarted. Both restart plays use any_errors_fatal
for cross-play guards. No range teardown, VM recreation beyond the earlier SEC,
forced SQL action, package reset, marker edit or content deletion was performed.

Intermediate logs and both verified backup paths were fetched into
.tmp/evidence/parent-servicing-checkpoint/cas-pss using local Ansible. Windows
JSON files have a UTF8 BOM; read them with utf-8-sig. These are intermediate
evidence, not acceptance. Current native retry follows its own schedule
(approximately 02:06 UTC after the latest failure). Keep monitoring the existing
coordinator/observer sessions, then finish parent 2609, create fresh SEC from
current PS1 media and run full three-site validation. Current installed artifact
and full config checksums remain in active-artifact-checksums.json (34f9fb34... /
2c21a951...). Collection create_contentlib_share was inspected but not modified;
functional tests do not justify new blanket ACL grants.

### October 27, 02:19 UTC: narrowed native file diagnostics

The normal PSS restart completed successfully. Native despooler retried at
02:09:48 and failed on another temporary DataLib INI file (ApplicationCatalog_CSY.cab.INI),
again with DeleteFile error 32 before the later access/rename errors. Both
parent sites remain 2509 and the 2609 package remains in content replication;
no release installation has started. Repeated guest restarts are not justified.

Both PSS and LIB have Windows Search disabled/stopped, Defender and Sense stopped,
and no third-party antivirus filesystem filter in the bounded fltmc output.
No security setting or ACL was changed. Two earlier built-in Kernel-File captures
stopped cleanly. The first covered an idle window; the second's broad keyword
mask filled its 96 MiB circular buffer and discarded the actual failure window.
The completed first trace parsed 742575 events with no library activity; the
second retained 83501 open/rename/delete events but none from the failed library
operation. These are diagnostic limitations, not evidence that no handle existed.

Narrowed bounded traces now capture file opens/renames/deletes on both PSS and
LIB through the next native retry. Their unique sessions stop in finally; no
managed-content files are edited, handles forcibly closed, or queue/status data
changed. A uniquely named disposable probe passed all 300 sequential native INI
write/read/replace/delete operations separately from SCCM-managed content;
its temporary folder was removed successfully (content-library-ini-sequences.log). Operational plays
and logs are under .tmp; installed collection and full-config checksums are
unchanged. Existing parent coordinator/observer continue; prerequisite timeout
is approximately 04:11 UTC. Finish parent servicing, create SEC from current
parent media, then perform three-site and client functional acceptance.

At 02:25 UTC the native import again failed on TotalPhysicalMemory.zh-CN,
EmailTemplate-MalwareOutbreak.zh-TW and RemediationScriptSettings.zh-TW INI
metadata within DataLib\TB0130000A. The narrowed traces stopped cleanly:
PSS LudusSccmFile_1077ae42309e (112295936 bytes, 06:16:04–06:29:04 guest UTC)
and LIB LudusSccmFile_f8f40ad6cab4 (81690624 bytes, 06:17:28–06:29:28 guest UTC).
Neither reached the 128 MiB limit. Both include the native failure window.
Decoders retain only the failed file opens plus the disposable positive-control
probe, and fetch filtered JSON into .tmp/evidence/file-sharing. Both hosts use
Windows build 20348.587; LIB share uses Full SMB leasing and SMB 3.1.1. These
settings are diagnostic observations; no SMB configuration has been changed.

### October 27, 03:01 UTC: file-lifetime trace captured; decoding

The 02:56:43 native retry failed again, finally on
DataLib\T6C140000A\redist\LanguagePack\Server\NLD\smssetup\Bin\x64\00000413\CMUpdateInstallationStatus.nl.resx.INI.
Earlier failures in this same attempt involved M365ASettings.cs.resx.INI and
RequiredAppsComplianceSettings.es.resx.INI. All show DeleteFile 32 followed by
rename errors. The native retry now waits until approximately 03:12:18.

The three-minute trace LudusSccmFile_6c74ee47f2ed stopped cleanly at guest UTC
06:58:41 (host 02:58:41), size 193396736 bytes, below its 512 MiB cap. It captures
file create, cleanup, close and operation-end events. Local decoder session1746,
.tmp/parse-failed-ini-file-lifetimes.yml with target_ini_name
CMUpdateInstallationStatus.nl.resx.INI, is correlating those events. Log:
.tmp/evidence/failed-ini-file-lifetimes.log. It uses cached field schemas from
the installed provider and maps only live IRPs/FileObjects; wait for the actual
result before inferring a leak or an SMB close issue.

A LIB-only Windows Update search completed with zero changes, zero installs and
no reboot. It offered KB5122882 (OS cumulative), KB5128928 (.NET cumulative) and
KB890830 (MSRT); no update has been selected or applied. The unsuccessful Shared
leasing trial was restored to Full, its source feature removed, and the reverted
collection rebuilt and installed for cthompson. Current archive SHA256 is
c4a2001f09644649c612c86f46aea29f6cab1350c8fd3053d9fc4fa12f3dd57e;
full config SHA256 is restored to 2c21a95173f3f2fcf58332d5a44503239401e4d3bb69a1f013710f6261514902.
Both current values are in active-artifact-checksums.json. No further primary
restart, OS update, native queue edit, manual content mutation or SQL action was
performed. Parent update is still pre-install; end-to-end acceptance is pending.

At 03:29:10, Windows System event 19 confirmed KB5122882 installed successfully.
Normal update-driven restarts completed; LIB reports 20348.5622. At 03:30:25,
System event 43 confirmed the pinned October KB5126655 installation started.
The same Ansible task 71091 continues; no .NET/MSRT selected. Do not run final
LIB verification or claim completion until the October update and restart finish.
Read-only monitor 76729 now also saves CBS stage percentages in its current JSON.
The full trace decoder completed 1009770 events / 220 target events, confirming the
short-window delayed-close finding; both outputs/finding are under file-sharing.

### October 27, 04:13 UTC: old coordinator wait ended; PSS maintenance continues

The original CAS release coordinator timed out at 04:11:26 waiting for 2609
prerequisites; rangeState is ERROR. Its logs show timeout, not a native installer
failure. No release installation was submitted. The old coordinator has ended;
its existing native content/prerequisite request remains queued. PSS maintenance
controller 5621 / watcher 82702 continue independently and must finish first.

PSS completed KB5122882, normal restarts, and now runs 20348.5622. October
KB5126655 installation started 04:08:38 and remains active. Both exact SCCM
services remain stopped/disabled with PID 0 by design; restore only after OS
servicing through the play's always block. Native 04:01 retry did not run while
those services were paused. LIB is already verified 20348.5761; its full patch
alone did not resolve the 03:46 sharing failure. Both machine-identity access
probes passed and cleaned up.

Resume only after PSS OS build/trust/service/lab-setting verification and native
content observation. The installed preparation-resume fix passed 46 mocked
behaviors/seven-file parse. Source SHA 1c1f320897a74ce46017dc04074f3818811c238388fd5256a545273ae1493113;
config SHA faf269a9c120cc73a21ac5cb22a308110251d89ebed8498fdc9f85599760aadd.
The next Ludus run should select only service_hierarchy on
localhost,cthompson-cas-pss with the full existing config; then restart the
read-only own-range/CAS monitors (old 95140 / 51797 have ended). Never duplicate a
live coordinator, reset native state or infer completion from an intermediate
two-site report. End-to-end goal remains pending.

### Enhanced HTTP prerequisite correction, October 27

After both SMB endpoints were updated, native content import succeeded at
04:23:59 and content replication at 04:25:23. Native 2609 prerequisites failed
at 04:26 with the explicit CAS HTTPS/Enhanced HTTP error and a retained NAA
usage warning. PS1 already has IISSSLState 1248 (Enhanced HTTP); CAS has 0.
The installed Microsoft Set-CMSite cmdlet confirms generated-certificate bit
1024 and HTTP mode normalization bits 64/128. The new opt-in per-site helper
uses that supported cmdlet, preserves HTTPS-only/already configured sites,
blocks anonymous DP access or an active update, and verifies unrelated flag
bits. The sample enables the option; the role default preserves existing mode.
54 offline PowerShell behaviors and seven-file parser checks passed, including
a mutation-free explicit preview, existing HTTPS preservation and failure guards.
Ansible syntax and collection build/install passed. Live preparation/recheck and
full current-release acceptance remain pending. NAA and client-approval settings
must be retained and checked before/after; native prerequisite errors remain
fatal. The guarded operational role selects only production package
8b9745e4-b815-49d6-8faa-5fdc8b3df4fc through Get-CMSiteUpdate and requests the
supported prerequisite retry, never a SQL state reset.

References: [Set-CMSite](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/set-cmsite?view=sccm-ps),
[Enhanced HTTP](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/hierarchy/enhanced-http),
[Invoke-CMSiteUpdatePrerequisiteCheck](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/invoke-cmsiteupdateprerequisitecheck?view=sccm-ps).

The guarded live preview passed with Preview=true, Changed=false and
PrerequisiteRetrySubmitted=false. It identified only CAS for modification,
retained PS1 mode 1248, and confirmed NAA/client-approval settings unchanged.
All update download/check/install actions now resolve the already selected GUID
to a native Get-CMSiteUpdate object before invoking the Microsoft cmdlet. Early
and broad 2609 packages have the same name; name-based actions are ambiguous.
56 offline behaviors passed, including exact selection among duplicate display
names and closed failure for missing/duplicate GUIDs. Existing resume/error/
warning cases still passed; seven files parsed. Live CAS application/recheck is
running through the explicit non-preview operational Ansible role.

### CAS-specific generated-certificate configuration, October 27, 12:50 EDT

The first supported Set-CMSite attempt did not change CAS and the guarded
five-minute wait failed without submitting prerequisites. Inspection of the
installed 2509 SetObjectProperties implementation confirmed that it calls
SetClientCommunicationProperties only for Type 2 (primary), even though CAS
Enhanced HTTP is supported. The corrected CAS path uses Get-CMSiteComponent,
checks exact component identity/FileType/current flags, and changes only the
generated-certificate bit through EmbeddedProperties and the documented native
IResultObject.Put method. Primary sites continue using Set-CMSite. This is a
site configuration change through the SDK; no SQL application-state rows change
outside the provider, and no readiness status is fabricated.

63 isolated offline behavior checks and seven-file parsing passed, including
SDK preview with zero Put calls, property preservation, identity/concurrent-mode
guards, idempotence, existing HTTPS and exact update GUID actions. The actual
SDK preview also passed with Changed=false, PrerequisiteRetrySubmitted=false,
CAS mode 0, PS1 mode 1248 and retained NAA/client approval. The guarded apply
and native prerequisite retry are now selected. All 15 VMs were confirmed
present and running after the interruption. Full acceptance remains pending.
SDK reference:
[Read and write the site control file](https://learn.microsoft.com/en-us/intune/configmgr/develop/core/understand/how-to-read-and-write-to-the-site-control-file-by-using-managed-code).

### Native warning policy, October 27, 13:00 EDT

The completed retry is state 131075 (warnings only). The first coordinator
reached this state and failed before installation in its separate CIM
SetIgnorePrereqWarning call (0x80041001). The installed native installer code
shows that Install-CMSiteUpdate maps SkipPrerequisiteCheck=false to PrereqFlag
0 and true to flag 2 (continue on warnings). It also writes that policy as part
of its supported pre-install request, so a separate earlier policy call would
be overwritten. The coordinator now uses this native switch with the reviewed
AllowWarnings value, after independently requiring both freshly read provider
and native package states to be 131074/131075. Missing/changing/error states
stop before invocation. Native setup still rejects errors. The package is bound
by GUID, and the lab's existing client-piloting configuration is preserved.
66 mocked behaviors and seven-file parsing passed, including warning permission
never admitting errors, final state-change guards and exact GUID selection.
The failed run made no installation request. Rebuild/install this correction and
resume one coordinator; no new prerequisite request or recovery copy is needed.

### Native SCP retry and console handoff, October 27

Both parents and the passive server reached 5.00.9152.1000. The SCP Executive
remained stopped on 2509 after its native stop/reinstall timed out; the component
manager deferred retry to its hourly poll. The saved maintenance play
`playbooks/retry_scp_component_installation.yml` passed a zero-change live
preview with installed local update, idle manager, healthy trust and no active
bootstrap work. One normal CAS component-manager restart was then performed.
Native reinstallation restored CAS-SCP Executive running at 5.0.9152.1003.
No SQL, credentials or permissions changed. Verification was corrected to
handle the service/executable being absent during replacement and passed.

The coordinator then reached hotfix servicing but refused the old root console,
reporting available version 5.2609.1050.1000. Root console refresh now runs in its
own PowerShell process before loading cmdlets, between parent release upgrades
and secondary/passive operations, and after hotfixes before final verification.
The first release phase has an explicit ParentsOnly mode; the second observes
the completed parents before reconciling remaining roles. Reruns refresh an
outdated console before reconnecting. No automatic console downgrade occurs.
74 offline behaviors and seven-file parsing passed, including new console
metadata/installer/version/restart guards. Live console update, component/client
completion, fresh SEC and final three-site acceptance remain pending.
