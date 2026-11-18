"""Background (async) tasks must not load the become user's profile.

Since the November 2026 Windows update, a profile loaded by the runas become
launcher is unloaded as soon as that launcher exits, so a background job that
loaded it fails on Start-Process or HKCU access ("registry key marked for
deletion"). These checks read the role files only.
"""

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
PHASE_INCLUDES = ("console.yml", "run_phase.yml", "phase_attempt.yml")


def task_files():
    for path in sorted((ROOT / "roles").glob("*/tasks/*")):
        if path.suffix in (".yml", ".yaml"):
            yield path


def walk(tasks, inherited, found):
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        own = task.get("vars") or {}
        flags = own.get("ansible_become_flags", inherited)
        for key in ("block", "rescue", "always"):
            if key in task:
                walk(task[key], flags, found)
        found.append((task, flags))


class AsyncBecomeTests(unittest.TestCase):
    def collect(self):
        found = []
        for path in task_files():
            tasks = yaml.safe_load(path.read_text())
            entries = []
            walk(tasks, None, entries)
            found.extend((path.relative_to(ROOT), task, flags) for task, flags in entries)
        return found

    def test_async_tasks_do_not_load_the_profile(self):
        checked = 0
        for path, task, flags in self.collect():
            if "async" not in task:
                continue
            checked += 1
            self.assertNotIn("with_profile", str(flags or ""), "%s: %s" % (path, task.get("name")))
        self.assertGreaterEqual(checked, 6)

    def test_phase_includes_do_not_pass_a_profile_flag(self):
        # Vars on the include itself outrank the phase task's own setting;
        # inherited block vars do not, so only the include's own vars matter.
        checked = 0
        for path, task, _ in self.collect():
            include = task.get("ansible.builtin.include_role") or task.get("ansible.builtin.include_tasks")
            target = include.get("tasks_from", "") if isinstance(include, dict) else str(include or "")
            if not target.endswith(PHASE_INCLUDES):
                continue
            checked += 1
            own = (task.get("vars") or {}).get("ansible_become_flags", "")
            self.assertNotIn("with_profile", str(own), "%s: %s" % (path, task.get("name")))
        self.assertGreaterEqual(checked, 3)

    def test_phase_attempt_sets_a_profile_free_flag(self):
        tasks = yaml.safe_load((ROOT / "roles/sccm_common/tasks/phase_attempt.yml").read_text())
        background = [t for t in tasks[0]["block"] if "async" in t]
        self.assertEqual(len(background), 1)
        self.assertEqual(background[0]["vars"]["ansible_become_flags"], "logon_type=interactive logon_flags=")


if __name__ == "__main__":
    unittest.main()
