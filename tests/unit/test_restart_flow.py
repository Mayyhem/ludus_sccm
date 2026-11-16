"""Exercise real Ansible includes/delegation with guest operations replaced."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('ansible-playbook'), 'Ansible is required')
class RestartFlowTests(unittest.TestCase):
    def run_flow(self, scenario):
        # Keep fixture state and all caches inside the authorized workspace.
        parent = ROOT / '.tmp' / 'restart-flow-tests'
        parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as directory:
            folder = Path(directory)
            fixtures = folder / 'collections'
            collection = fixtures / 'ansible_collections' / 'ansible' / 'windows'
            actions = collection / 'plugins' / 'action'
            modules = collection / 'plugins' / 'modules'
            actions.mkdir(parents=True)
            modules.mkdir(parents=True)
            fixture_code = (ROOT / 'tests/fixtures/restart_flow/action.py').read_text()
            for name in ['win_powershell', 'win_reboot', 'win_copy']:
                (actions / f'{name}.py').write_text(fixture_code)
                (modules / f'{name}.py').write_text('DOCUMENTATION = """---\nmodule: '+name+'\nshort_description: Isolated fixture\ndescription: [Isolated fixture]\noptions: {}\n"""\n')
            inventory = folder / 'inventory.yml'
            inventory.write_text('all:\n  hosts:\n    controller:\n      ansible_connection: local\n    cthompson-ps1-dev:\n      ansible_connection: winrm\n      ansible_host: 127.0.0.1\n    cthompson-ps1-db:\n      ansible_connection: winrm\n      ansible_host: 127.0.0.1\n')
            state = folder / 'state.json'
            env = dict(os.environ)
            env['ANSIBLE_COLLECTIONS_PATH'] = str(fixtures)+os.pathsep+str(ROOT / '.tmp/collections')
            env['SCCM_RESTART_TEST_STATE'] = str(state)
            env['SCCM_RESTART_TEST_CASE'] = scenario
            env['ANSIBLE_NOCOLOR'] = '1'
            command = ['ansible-playbook', '-i', str(inventory), str(ROOT / 'tests/integration/restart_flow.yml')]
            if scenario == 'disabled':
                command.extend(['-e', 'ludus_sccm_automatic_reboots=false'])
            if scenario == 'two_phases':
                command.extend(['-e', 'sccm_test_repeat_phase=true'])
            run = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=90)
            return run, json.loads(state.read_text()) if state.exists() else {}

    def test_checkpoint_reboots_then_resumes_once(self):
        run, state = self.run_flow('success')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertEqual(state['phases'], 2)
        self.assertEqual(state['restarts'], 1)
        self.assertEqual(state['events'], ['phase-exited', 'guest-guarded', 'guest-rebooted', 'guest-verified', 'phase-exited'])

    def test_repeated_request_stops_at_limit(self):
        run, state = self.run_flow('limit')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(state['phases'], 3, run.stdout+run.stderr)
        self.assertEqual(state['restarts'], 2)
        self.assertIn('exceeded its restart limit', run.stdout)

    def test_multiple_guests_finish_serially_on_their_exact_targets(self):
        run, state = self.run_flow('multiple')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertEqual(state['phases'], 2)
        self.assertEqual(state['restarts'], 2)
        self.assertEqual(state['targets'], [
            [event, target]
            for target in ['cthompson-ps1-dev', 'cthompson-ps1-db']
            for event in ['guest-guarded', 'guest-rebooted', 'guest-verified']
        ])

    def test_adjacent_phases_each_restart_and_resume_independently(self):
        run, state = self.run_flow('two_phases')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertEqual(state['phases'], 4)
        self.assertEqual(state['restarts'], 2)
        self.assertEqual(state['groups'], {'CAS': 2, 'PS1': 2})

    def test_unmapped_target_never_reboots(self):
        run, state = self.run_flow('unmapped')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(state['restarts'], 0)
        self.assertIn('not a Windows guest in this range inventory', run.stdout)

    def test_disabled_policy_never_reboots(self):
        run, state = self.run_flow('disabled')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(state['restarts'], 0)
        self.assertIn('Automatic restarts are disabled', run.stdout)
