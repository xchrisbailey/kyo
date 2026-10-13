import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], text=True, capture_output=True, **kwargs)


class Guards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def lint(self, source, update=False):
        (self.root / 'Kyo').mkdir(exist_ok=True)
        (self.root / 'Kyo/view.swift').write_text(source)
        return run(ROOT / 'scripts/lint-accessibility-identifiers', '--root', self.root,
                   *(['--update-baseline'] if update else []))

    def test_stable_identifiers(self):
        result = self.lint('Text("a").accessibilityIdentifier("task-row-\\(task.id.uuidString)")\n'
                           'Text("b").accessibilityIdentifier("section-header-tasks")')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_bad_prefixes_and_display_text(self):
        for identifier in ['TaskRow', 'task_row', 'task:row', 'task-row-\\(task.text)', 'project-row-\\(project.name)']:
            with self.subTest(identifier=identifier):
                result = self.lint(f'Text("a").accessibilityIdentifier("{identifier}")')
                self.assertEqual(result.returncode, 1)

    def test_comments_and_string_contents_are_not_modifier_calls(self):
        source = '\n'.join(['// .accessibilityIdentifier("WrongName")',
                            '/* nested /* comment */ .accessibilityIdentifier("Bad") */',
                            'let example = "literal .accessibilityIdentifier"',
                            'Text("a").accessibilityIdentifier(\n"valid-prefix-\\(task.id.uuidString)"\n)'])
        self.assertEqual(self.lint(source).returncode, 0)

    def test_unknown_expression_requires_review(self):
        self.assertEqual(self.lint('Text("a").accessibilityIdentifier(identifier)').returncode, 1)

    def test_baseline_does_not_allow_new_occurrences(self):
        source = 'Text("a").accessibilityIdentifier("OldName")\n'
        self.assertEqual(self.lint(source, update=True).returncode, 0)
        self.assertEqual(self.lint(source).returncode, 0)
        self.assertEqual(self.lint(source * 2).returncode, 1)
        result = self.lint('Text("a").accessibilityIdentifier("new-name")')
        self.assertEqual(result.returncode, 0)
        self.assertIn('Baseline can shrink', result.stdout)

    def evidence(self, body, status=0, *selectors):
        log = self.root / 'run.log'
        log.write_text(body + '\n** TEST SUCCEEDED **\n')
        return run(ROOT / 'scripts/validate-test-run', log, status, *selectors)

    def test_executed_xctest_and_selected_test(self):
        body = "Test Case '-[KyoTests.Example testReal]' passed (0.1 seconds).\nExecuted 1 test, with 0 failures"
        self.assertEqual(self.evidence(body, 0, '-only-testing:KyoTests/Example/testReal').returncode, 0)
        self.assertEqual(self.evidence(body, 0, '-only-testing:KyoTests/Example').returncode, 0)
        self.assertEqual(self.evidence(body, 0, '-only-testing:KyoTests/Example/testMissing').returncode, 65)

    def test_zero_missing_and_all_skipped(self):
        for body in ['', 'Executed 0 tests, with 0 failures',
                     "Test Case '-[KyoTests.Example testReal]' skipped (0.1 seconds).\nExecuted 1 test, with 1 test skipped and 0 failures"]:
            with self.subTest(body=body):
                self.assertEqual(self.evidence(body).returncode, 65)

    def test_swift_testing(self):
        body = 'Executed 0 tests, with 0 failures\n✔ Test stableOrdering() passed after 0.001 seconds.\n✔ Test run with 1 test passed after 0.001 seconds.'
        self.assertEqual(self.evidence(body).returncode, 0)
        self.assertEqual(self.evidence(body, 0, '-only-testing:KyoTests').returncode, 0)
        self.assertEqual(self.evidence(body, 0, '-only-testing:KyoTests/stableOrdering').returncode, 0)
        suite_body = body + '\n✔ Suite "Ordering" passed after 0.001 seconds.'
        self.assertEqual(self.evidence(suite_body, 0, '-only-testing:KyoTests/Ordering').returncode, 0)
        self.assertEqual(self.evidence(suite_body, 0, '-only-testing:KyoTests/Missing').returncode, 65)
        self.assertEqual(self.evidence('↷ Test optional() skipped.\n✔ Test run with 1 test passed after 0.001 seconds.').returncode, 65)

    def test_genuine_failure_status_is_preserved(self):
        self.assertEqual(self.evidence('', 70).returncode, 70)

    def test_test_controller_wires_guard_and_retains_failure_status(self):
        tools = self.root / 'bin'
        tools.mkdir()
        (tools / 'xcrun').write_text('#!/bin/sh\ncase "$*" in\n*"list runtimes"*) echo "iOS 27.0 (27.0) - com.apple.CoreSimulator.SimRuntime.iOS-27-0";;\n*"create"*) echo fixture-udid;;\nesac\n')
        builder = tools / 'xcodebuild'
        for binary in tools.iterdir():
            binary.chmod(0o755)
        env = {**os.environ, 'PATH': f'{tools}:{os.environ["PATH"]}', 'TMPDIR': str(self.root)}
        for body, status, expected in [('Executed 0 tests, with 0 failures', 0, 65),
                                       ('Executed 1 test, with 0 failures', 0, 0), ('', 70, 70)]:
            builder.write_text(f'#!/bin/sh\necho "{body}"\necho "** TEST SUCCEEDED **"\nexit {status}\n')
            builder.chmod(0o755)
            result = run(ROOT / 'scripts/test', '--platform', 'ios', 'FixtureTests', env=env)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_round_trip_preflight_does_not_call_device_tools(self):
        tools = self.root / 'bin'
        tools.mkdir()
        marker = self.root / 'called'
        for name in ['xcodebuild', 'xcrun']:
            binary = tools / name
            binary.write_text(f'#!/bin/sh\ntouch "{marker}"\nexit 99\n')
            binary.chmod(0o755)
        result = run(ROOT / 'scripts/test', '--paired-projects', env={**os.environ, 'PATH': f'{tools}:{os.environ["PATH"]}'})
        self.assertEqual(result.returncode, 2)
        self.assertIn('physical', result.stderr)
        self.assertFalse(marker.exists())

    def test_live_status_concurrent_run_and_completed_gate(self):
        repo = self.root / 'repo'
        shutil.copytree(ROOT / 'scripts', repo / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['test', 'test-tooling', 'lint-accessibility-identifiers']:
            path = repo / 'scripts' / name
            path.write_text('#!/bin/sh\necho "** TEST SUCCEEDED **"\n')
            path.chmod(0o755)
        run('git', 'init', '-q', repo, check=True)
        run('git', '-C', repo, 'add', '.', check=True)
        run('git', '-C', repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '-qm', 'fixture', check=True)
        sha = run('git', '-C', repo, 'rev-parse', 'HEAD', check=True).stdout.strip()
        tools = self.root / 'bin'
        tools.mkdir()
        release = self.root / 'release'
        binary = tools / 'xcodebuild'
        binary.write_text(f'#!/bin/sh\nwhile [ ! -f "{release}" ]; do sleep 0.1; done\necho "** BUILD SUCCEEDED **"\n')
        binary.chmod(0o755)
        env = {**os.environ, 'PATH': f'{tools}:{os.environ["PATH"]}', 'TMPDIR': str(self.root)}
        check = repo / 'scripts/check'
        with subprocess.Popen([str(check), '--base', sha], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    result = run(check, '--status', sha, env=env)
                    data = json.loads(result.stdout)
                    if data.get('phase') == 'build Kyo':
                        break
                    time.sleep(0.05)
                self.assertEqual(data['commit'], sha)
                self.assertEqual(data['state'], 'running')
                self.assertIn('build-kyo.log', data['log'])
                self.assertEqual(run(check, '--base', sha, env=env).returncode, 2)
                self.assertEqual(run(check, '--show', sha, env=env).returncode, 2)
            finally:
                release.touch()
                stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, stdout + stderr)
        self.assertEqual(run(check, '--show', sha, env=env).returncode, 0)
        final = json.loads(run(check, '--status', sha, env=env).stdout)
        self.assertEqual((final['state'], final['outcome']), ('completed', 'PASS'))
        (self.root / 'kyo-check' / f'{sha}.txt').unlink()
        final = json.loads(run(check, '--status', sha, env=env).stdout)
        self.assertIsNone(final['outcome'])

    def test_stale_process_is_interrupted_not_pass(self):
        directory = self.root / 'kyo-check'
        directory.mkdir()
        (directory / 'fixture.json').write_text(json.dumps(dict(commit='fixture', pid=99999999, process_start='old',
            started_at=time.time(), state='running', outcome=None, phase='test', log=None)))
        result = run(ROOT / 'scripts/check-progress', 'status', 'fixture', env={**os.environ, 'TMPDIR': str(self.root)})
        data = json.loads(result.stdout)
        self.assertEqual(data['state'], 'interrupted')
        self.assertIsNone(data['outcome'])
        result = run(ROOT / 'scripts/check-progress', 'watch', 'fixture', '--seconds', 61,
                     env={**os.environ, 'TMPDIR': str(self.root)})
        self.assertEqual(result.returncode, 2)
