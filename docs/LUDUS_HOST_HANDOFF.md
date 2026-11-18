# Handoff to the agent on the Ludus host

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

## Historical resume, October 26, 2026

The live Microsoft Learn Markdown endpoint now announces 2609 broad availability
on October 26. The cached web response still showed early access. The retry's
controller correctly rejected the newly broad, previously unknown release; native
SEC recovery continues independently. The reviewed catalog now understands 2609
(build 9152, upgrade floor 2503). This fresh range uses SQL 2022, ADK 26100 and
ODBC 18.6.2.1, which meet its requirements. Do not install ODBC 18.7.1.1 while
still on 2509. SCCM 2609 setup owns its OLE DB / Visual C++ updates. The current
fresh route is 2509 -> 2609, matching the owner's current-release objective.
43 Python checks passed, including broad/early channel handling and routes.
Collection build/isolated install, planner integration normal/check mode, and
deployment syntax passed. Source SHA-256 `ee23c68d72599aa8acff1fa9329a027f8eb6db810aaf41af5599df2af3d20eff` is
installed for cthompson. The full `.tmp/cthompson-latest.yml` config is restored;
only normal secondary readiness, hierarchy servicing and SQL verification are
selected. The temporary recovery role is no longer assigned. Final live acceptance
is pending. Evidence:
`.tmp/evidence/release-evidence/2609.md`, `2609-changes.md`, and
`.tmp/evidence/version-plan-2609.json`.

The owner approved the four passive-account local administrator grants, which
were applied through Ludus/Ansible and independently verified. The role also
applied PS1-SEC's assignment already present in the original config; this fifth
pending assignment was missed in the prior four-host list and disclosed. Passive
HA stages 11–14 completed, promotion is unrequested, and the CAS/PS1 link had
86 ready replication groups. All 15 VMs and the expected 14 Windows DNS records
were verified. Both primary/CAS sites remain installed at baseline 2509.

SEC setup completed after its post-feature restart restored remote WMI access.
The preparation role now encodes this restart. The interrupted bootstrap monitor
left the parent reporting failure despite running guest services. An initial
create retry was rejected by prerequisites because the site already exists. A
later documented generic recovery-property write was accepted but did not launch
recovery; HMAN restored the old failure state. A COPY_ONLY database backup was
verified, and secondary/model compatibility was set to 150 through Ansible.
SCCM secondary recovery uses parent-driven reinstallation/reinitialization, not
that backup. Before the approved recovery, no site, database, VM or range had been
deleted; the native retry has now successfully replaced the old CM_SEC database. Never duplicate active
vendor setup or treat running services alone as proof of parent readiness.

The publishing template now includes configured passive/secondary computer
accounts. Its rendered preview parsed successfully and left the directory ACL
unchanged. Automatic approval review initially rejected applying these grants.
The owner explicitly approved Full Control for `MAYYHEM\PS1-PSV$` and
`MAYYHEM\PS1-SEC$` on `CN=System Management,CN=System,DC=mayyhem,DC=com`
and its child objects. Both approved grants were applied through the tracked
template and verified;
the second run left the ACL unchanged. PS1-PSS's grant already existed. No other
container was selected.

The newest source also enforces supported secondary database/model compatibility
after actual readiness. Collection build/isolated install, both integration
syntax checks, 36 mocked Windows behavior checks and 63 PowerShell parser checks
pass. The tested source is installed in the user-scoped runtime (artifact SHA-256
`616b0ec37778faf4d1d6293764643075554b12f99da05a6035e6af11bb333f0e`).
The remote SMS Provider installation succeeded. Both providers still report SEC
failed. HMAN observed the prior generic 1011 property write and returned to the
old failure without launching recovery. Inspection of the installed Microsoft
console action identified the actual request: preserve the site-control request
flags, set its pending request values to 2 / 1011 (or 1012 for existing source),
request vendor prerequisites, then save the site definition through the SDK.
The guarded Ansible recovery script checks exact identity, baseline version,
running service, no primary/secondary setup, and the verified backup before any
request. It never writes the read-only SMS_Site.Status or a healthy state.
Automatic approval review initially rejected submission because recovery can
reinstall/reinitialize SEC. The separate preview passed with WhatIf and
Submitted=false, confirming the exact SEC target, running baseline service,
no setup processes and existing verified backup. The owner then explicitly
approved SEC recovery and continuation on October 26. The guarded recovery,
secondary readiness, SQL verification and hierarchy servicing are resumed using
`.tmp/cthompson-supported-secondary-recovery.yml`. This retains every original
role and adds an ordering edge so readiness follows the recovery request.
Recovery setup reached SQL database reinitialization but waited in
PRINT_ROLLBACK_PROGRESS while the old SMS Message Processing Engine retained a
connection. A guarded Ansible task (`.tmp/quiesce-secondary-recovery.yml`)
verified the active recovery/log/SQL wait and stopped only SEC's Site Component
Manager and Executive, keeping SQL and setup running. The operational recovery
script now quiesces those old services inside ShouldProcess before submitting
recovery, and waits for their old processes to exit. A later guarded task found the old
process already gone, so no process was terminated. SQL still retained its
sleeping session 110 (old client PID 5324, zero open transactions);
`.tmp/disconnect-secondary-orphan.yml` closed that exact orphan under the
approved recovery, preserving SQL and setup. The operational request script
now closes only captured old-worker orphan connections before its SDK request. Do not resubmit
while this vendor setup is active.
The disconnected SQL session persisted after KILL, and the approved normal
SQL restart stalled in StopPending. Automatic approval review rejected a
proposed forced termination due corruption/data-loss risk. A supposed preview
then unintentionally terminated SQL PID 2852: win_powershell overwrites direct
WhatIf parameters with its check-mode value. The owner was immediately told;
no specific force approval was received and no repeat is authorized. SQL
restarted as PID 5488, startup recovery completed, and native SEC recovery
advanced past the blocked database step. CHECKDB passed for master, model and msdb with zero consistency errors and no
repair. Corrected preview/approval guards passed three mocked cases with zero mutation
calls; CM_SEC consistency
must also be checked after native setup completes. The force task now defaults to an explicit
Preview return before mutations and a separate ForceApproved=false gate.
See `.tmp/evidence/force-sql-restart-preview.log`,
`secondary-state-after-forced-stop.log`, and `assess-secondary-sql.log`.
The first native recovery exited at 6:26 PM America/New_York on October 26
with database-initialization failure. The SQL interruption caused its SINGLE_USER /
drop operation to fail; setup then rejected the retained CM_SEC database's 5418
objects. The misleading final Completed marker and setup exit code 0 do not mean
success: SMS_BOOTSTRAP explicitly reported failure. The readiness wait was
aborted; all 15 VMs remain running. SQL is running, CM_SEC is ONLINE / MULTI_USER,
and no user sessions or native setup processes remain. CHECKDB also passed for
CM_SEC with zero consistency errors and no repair. Native setup removed its
SCCM services during the failed reinstall. The revised guarded recovery accepts
that partial state only when the parent reports failed recovery (9), retains the
baseline version/identity/backup checks, stops existing SCCM services gracefully,
and refuses submission if any CM_SEC user connection remains. No forced process
termination or SQL KILL remains in the revised request script. Native SCCM alone
owns database replacement. Parse-only validation passed. The read-only provider check confirmed Status 9. Preview returned Submitted=false
and the approved retry returned Submitted=true. Native SCCM successfully dropped
the old CM_SEC at 6:40 PM America/New_York; no forced SQL operation occurred.
Setup completed the approximately 20-minute default-instance discovery loop and
created the new CM_SEC at 7:02 PM America/New_York, compatibility 150. Native
schema installation completed. SEC SQL, SMS Executive and Site Component Manager
are running. Native setup now waits for replication reinitialization. Both ends
track GUID `2febc7b9-480d-4bf4-b279-14744fb2a2c1` at PendingCreation (3), 21%;
PS1 package request remains Requested (0). HMAN created its SEC route at 7:06 PM
America/New_York; earlier missing-route errors predate this, and current routes
exist both ways with no broker transmission backlog. SQL shows no blocking or
active export. A guarded normal Ansible restart of only PS1 SMS_EXECUTIVE was
started to reload its idle export workers. It preserves SQL and SEC setup, does
not force any process, and does not resubmit initialization or edit tracking data.
See `.tmp/evidence/secondary-initialization-tracking.log` and
`restart-primary-export-worker.log`. Parent reinitialization and new-database
consistency verification remain pending. Do not interrupt or resubmit.
No range teardown is authorized. The report destination stays within this
workspace. The guarded task submitted the 2 / 1011 request successfully. Native SCCM
prerequisites passed, recovery job 00000063 was created, and SEC entered recovery
in progress (Status 8), but that first attempt subsequently failed as described above.
Check the live deployment before issuing any further request.
Evidence: `.tmp/evidence/secondary-console-recovery-preview.json`,
`recovery-console-methods.log`, `recovery-console-commit.log`, and
`.tmp/cthompson_secondary_recovery/files/Request-InstalledSecondaryRecovery.ps1`.
Full current-release servicing/hotfix/component acceptance is pending. Temporary diagnostics
retain every original role assignment and select
only their own role; a SUCCESS diagnostic is not deployment completion. See
`.tmp/evidence/permission-approval-checkpoint.json` for the current config/artifact
and `.tmp/evidence/recovery-validation.json` for the provider state.

## Current host-session scope and checkpoint, October 23, 2026

The owner authorized end-to-end fresh deployment of the current broad release
only in the empty `cthompson` range. Every Ludus command must include
`--user cthompson`; use `--range cthompson` for range operations. Do not access
other users/ranges or directly inspect/edit host files outside
`/home/cthompson/ludus_sccm`. Guest restarts and redeploys are allowed at any
time, but tearing down the range requires the owner's permission. A coordinated
pre-existing recovery point is waived for this fresh range. These current
instructions supersede the original Windows workspace and existing-lab test
scope below. See the October 23 checkpoint in [the plan](../UPGRADE_PLAN.md).

Linux build, isolated collection installation, module documentation, planner
execution/check mode, and role syntax checks pass. Forty unit tests and YAML
checks pass. A fresh release lookup selects 2603 from baseline 2509 with hotfixes
enabled. The full configuration was accepted for the empty range. The owner
manually repaired permissions on the user-scoped SCCM collection after Ludus
could not replace/remove it. Installation of the exact existing test commit
then succeeded through `ludus --user cthompson`, without sudo or direct file
access outside the repository. After an unexpected host reboot, the existing
15 guests were restarted and SQL/site prerequisites resumed successfully.
The 2509 media's 7-Zip SFX switches and folder layout differed from legacy
media. The fix passed 27 Windows PowerShell behavior checks, parsing of 61
files, and actual extraction/signature/build verification (`5.0.9141.1002`),
and was installed for `cthompson` through source `cthompson-sccm-fixed-test`.
Deployment resumed with `--tags user-defined-roles`, passed media verification
on both site servers, and started PS1 site setup at about 18:25 UTC. Setup is
downloading/verifying Microsoft prerequisites. Site/servicing acceptance
remains pending. PS1's first setup subsequently failed its OLE DB prerequisite
because x86 Visual C++ was missing. The collection now verifies both runtime
architectures independently of ODBC. Forty Python tests, 31 PowerShell behavior
checks, and Linux/Windows syntax checks pass. A live repair installed both
runtimes and the previously failing OLE DB MSI successfully; PS1 restarted and
role deployment resumed at approximately 18:35 UTC. No site or range was removed.
The new PS1 setup started around 18:46 UTC and passed the repaired prerequisite.
By 18:58 it had finished initial data import and was creating database keys.
Full Version now exists (`5.00.9141.1000`), while setup completion/service
readiness remains pending. Preserve this in-progress site; do not reinstall it
just because its final service is not ready yet.
At about 19:08 UTC PS1 setup and console checks passed; SMS Executive is running.
The subsequent push GPO was created/imported/linked, but remote policy refresh
failed with Access Denied. A tested WinRM/local computer-policy refresh change
is installed, and `cthompson_policy_validation` is being run alone to verify
check mode, the exact 13 member-computer targets, and live refresh. Its temporary
config is `.tmp/cthompson-policy-test.yml`. Restore `.tmp/cthompson-latest.yml`
after that check before resuming the remaining collection roles. Preserve the
installed PS1 site. CAS/secondary/passive installation and servicing are pending.
The policy validation passed around 19:17 UTC: check mode had no changes and
exactly the 13 intended member targets; every actual refresh returned exit zero.
The main `.tmp/cthompson-latest.yml` config is restored, and the remaining
collection roles are deploying again. Policy validation is no longer attached
to the active config. Current offline Windows results: 34 behavior checks and
62 parsed files. Preserve PS1; full hierarchy/servicing acceptance remains pending.
The following main run passed policy refresh and discovery, then found the
default controller PXE ISO missing. Optional URL/SHA-256 ISO acquisition is now
implemented in the primary-site role and configured on PS1 using the official
Windows 11 LTSC 2024 x64 evaluation ISO. Actual automated acquisition and an
unchanged rerun passed; the collection is installed, the main config includes
the media settings, and deployment is running again. See the plan for exact
URL/hash/evidence. All persistent repairs must remain encoded in automation,
as the owner explicitly clarified. No shared ISO store was inspected/changed.
The main role passed PXE media verification, WIM/OS image creation/distribution,
and task-sequence creation around 19:51 UTC. PS1 post-install configuration is
complete. CAS-PSS started fresh setup around 19:52 UTC; its pre-install restart
and SQL connectivity checks passed. The range is deploying, with PS1 preserved.
Remaining hierarchy/servicing and full acceptance are still pending.
CAS setup and console checks passed around 20:20 UTC. Its runtimes and OLE DB
were installed successfully by the normal automation, independently of PS1's
repair test. Both site component services are running and RCM reports the
CAS/PS1 expansion link completed. Deployment has advanced to remaining site
systems. Eleven baseline clients are running at `5.00.9141.1011`, assigned to
PS1; all 14 Windows guests were reachable. Final servicing and remaining roles
are pending. Preserve both installed sites.
The passive server's vendor setup has completed and its component services are
running at the baseline build. At 20:38 UTC the active server is still installing
passive components; HA-stage readiness is pending. The range is still deploying.
Subsequent read-only Ludus diagnostics identified HA stage 14 failure: the
passive machine account cannot access PS1-MP's ADMIN$ share. Both sites are
active and all 86 replication groups are ready. The sample config now orders
all passive-admin tasks before passive installation and adds the missing DB
host assignment; the helper now reports failed HA substeps immediately. These
changes pass 36 Windows behavior checks, 62 parses, YAML/dependency validation,
collection build/install and integration syntax checks. Applying the required
four new local-Administrators memberships (PS1-DB/DP/MP/SMS) was rejected by
automatic approval review pending explicit authorization. No grant executed;
the full deployment is paused, with both installed sites preserved. A SUCCESS
state from the temporary read-only diagnostic is not deployment acceptance.
The corrected permission configuration is prepared in `.tmp/cthompson-latest.yml`
but has not been applied. See the plan for the exact account and evidence.
See the plan for the current checkpoint and the
safe local source-upload workflow; no range teardown has occurred.

The installed Ludus version is 2.3.2+bba3dd3a. Archive URLs are incorrectly
treated as Git sources on this server. Fetching the existing committed test
branch through a temporary loopback Git source worked, then installation hit
the same permissions problem; retrying after the owner's repair succeeded.
Both temporary HTTP servers are stopped. Do not
repeat the archive instructions below without accounting for these findings.

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

### October 27 UTC: guarded SEC-only guest recreation in progress

Native SEC recovery recreated CM_SEC and core services, but the initial
Secondary_Site_Replication_Configuration group remained PendingCreation at 21%.
PS1's normal SMS Executive restart and one supported InitializeData request did
not start a package export. The installed RLA returned NotApplicable with zero
rules and no remediation. No replication status or SQL application rows were
changed manually. No release update has yet started.

The owner's earlier permission allows individual guest redeploys at any time.
A guarded SEC-only rebuild is now being prepared. Target: cthompson-ps1-sec,
VM 189, 10.1.11.200; retain the other 14 guests, CAS, PS1 and the range. Native
Remove-CMSecondarySite -Action Delete handles only SEC's failed registration.
Preview confirmed SEC Status 8 under PS1, both parent sites active on 9141,
Submitted=false. Four mocked negative guards and one exact-target positive
case passed, with no real provider calls. Ansible deployment syntax passed.
Normal SEC service stop was submitted; no forced SQL stop is authorized. At
this checkpoint no site metadata or VM has been deleted.

Operational scripts/configs live in .tmp/cthompson_secondary_redeploy,
.tmp/stop-secondary-for-redeploy.yml, .tmp/shutdown-secondary-for-redeploy.yml
and .tmp/guard-sec-destroy.py. The VM guard requires completed metadata deletion,
a powered-off exact VM 189, and unchanged names, IDs, addresses and power state
for all other 14 guests. Never destroy the range. After recreation, rediscover
the SEC VM ID and own-range inventory. Service the retained parent sites to
2609 before creating the new secondary from their current media; a temporary
two-site report is not acceptance.

Installed cache-path collection artifact SHA256:
f74efebf72ac44f52bf62071aba1025abc370ad1de50261b31227f6fb6c7648a.
The full cthompson config now sets each VM's ludus_sccm_cache_directory to
/home/cthompson/ludus_sccm/.tmp/cache/sccm-downloads, retaining all original roles
and dependencies. The default cache remains /opt/ludus/resources/sccm for other
installations. Current checksums are in .tmp/evidence/active-artifact-checksums.json.

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

### October 27, 01:11 UTC: parent servicing resumed, SEC OS prepared

Only SEC was recreated under the owner's explicit any-time guest-redeploy
permission. The other 14 VMs and the range were verified intact. Replacement
SEC reused VM 189 at 10.1.11.200, retained its AD computer SID/GUID, and passed
Windows/domain provisioning, SCCM prerequisites, and primary-machine-account
DCOM/WMI plus ADMIN$ read checks. No SCCM secondary is registered on it yet.
All 15 VMs are running. CAS and PS1 remain active on 2509 with 86 ready groups.

Two parent-servicing failures occurred before any release installation was
submitted. First, network Copy-Item resolved against the current CMSite drive.
The shared Copy-SccmFile helper now qualifies filesystem paths for recovery,
console/client and secondary SQL copies. Second, Invoke-CMSiteUpdateCheck
returned the known 'Still checking for updates' response. The shared wrapper
now observes this known busy condition and leaves all other errors fatal;
busy hotfix rounds do not count as settled empty catalogs. Seven files parsed,
39 PowerShell behavior checks and three real CMSite transfer variants passed.

The latest installed artifact SHA256 is
34f9fb34a6ed3e174885316db36b5f250c69c608d223c05fb3bd905d0443e821.
Full active config remains .tmp/cthompson-latest.yml, SHA256
2c21a95173f3f2fcf58332d5a44503239401e4d3bb69a1f013710f6261514902,
with all original roles/dependencies, latest/hotfixes true, project paths and
direct guest downloads enabled. No controller-cache/home permissions changed.
The normal 2609 package is 8b9745e4-b815-49d6-8faa-5fdc8b3df4fc (9152.1000);
the older eeb7bd91 entry is not applicable and is excluded. No early-ring opt-in.

Current Ludus selection: only service_hierarchy on localhost,CAS-PSS; full
config remains assigned. Backup verification completed for CAS and its
CD.Latest copy succeeded with the fix. PS1 backup/media preparation is running.
Monitor sessions 95140 (range) and 51797 (read-only native observer). Observer
writes .tmp/evidence/hierarchy-servicing-current.json/log. The worker cannot
fetch directly into the protected project path; use the existing local Ansible
fetch fallback to retain reports here after servicing. Do not change host home
permissions or inspect files outside this workspace.

Next: finish the two-parent 2609 stage, create SEC from updated PS1 media using
the existing secondary-install role, then run servicing and all acceptance
checks for three sites. An intermediate two-site report is not goal acceptance.
No range teardown, site-status edits, forced SQL termination or duplicate
secondary recovery/reinitialization are authorized or needed for this stage.

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
