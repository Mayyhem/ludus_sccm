"""Controller-only fixture: no guest connection or native operation is performed."""
import json
import os
from pathlib import Path

from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        # The fixture completes synchronously; native async polling is not simulated.
        self._task.async_val = 0
        args = self._task.args
        path = Path(os.environ['SCCM_RESTART_TEST_STATE'])
        state = json.loads(path.read_text()) if path.exists() else {'phases': 0, 'restarts': 0, 'events': []}
        module = self._task.action.rsplit('.', 1)[-1]
        result = {'changed': False}
        scenario = os.environ.get('SCCM_RESTART_TEST_CASE')

        def record_guest(event):
            target = self._templar.template(self._task.delegate_to)
            request = task_vars['sccm_restart_request']
            expected = 'cthompson-' + request['Computer'].split('.')[0].lower()
            if target != expected:
                raise AssertionError(f'{event} delegated to {target}, expected {expected}')
            state.setdefault('targets', []).append([event, target])
            state['events'].append(event)

        if module == 'win_powershell':
            parameters = args.get('parameters', {})
            if 'Phase' in parameters:
                state['phases'] += 1
                state['events'].append('phase-exited')
                site = parameters['Arguments']['SiteCode']
                groups = state.setdefault('groups', {})
                groups[site] = groups.get(site, 0) + 1
                need_restart = groups[site] == 1 or scenario == 'limit'
                request = {'Computer': 'ps1-dev.mayyhem.com', 'Kind': 'Client', 'Version': '5.00.9152.1006', 'SiteCode': 'PS1', 'BootTimeUtc': 'fixture-boot', 'PackageGuid': ''}
                if scenario == 'unmapped':
                    request['Computer'] = 'outside.mayyhem.com'
                requests = [request]
                if scenario == 'multiple':
                    requests.append(dict(request, Computer='ps1-db.mayyhem.com'))
                result['result'] = {'Complete': not need_restart, 'Changed': False, 'RebootRequests': requests if need_restart else []}
            elif 'Test-SccmGuestAfterRestart' in args.get('script', ''):
                record_guest('guest-verified')
                result['result'] = {'Ready': True, 'Computer': 'PS1-DEV'}
            else:
                record_guest('guest-guarded')
                result['result'] = {'NeedsRestart': True}
        elif module == 'win_reboot':
            if not state['events'] or state['events'][-1] != 'guest-guarded':
                raise AssertionError('A guest was rebooted before its phase exited and its guard passed.')
            record_guest('guest-rebooted')
            state['restarts'] += 1
            result['changed'] = True
        path.write_text(json.dumps(state))
        return result
