"""Run real release shell steps against local git and mocked publication APIs.

Requires Ruby (standard-library YAML/JSON) and Python 3. No production credentials.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

WORKFLOW = Path(os.environ.get("RELEASE_WORKFLOW", ".github/workflows/release.yml")).resolve()
WORKFLOW_DATA = json.loads(subprocess.check_output([
    "ruby", "-ryaml", "-rjson", "-e",
    "puts JSON.generate(YAML.load_file(ARGV[0]))", str(WORKFLOW),
], text=True))
STEPS = {step.get("name"): step for step in WORKFLOW_DATA["jobs"]["release"]["steps"]}


class ReleaseContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.remote = self.root / "remote.git"
        self.repo.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "output"
        self.output.touch()
        self.summary = self.root / "summary"
        self.calls = self.root / "calls"
        self.pr = self.root / "pr"
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        GITHUB_OUTPUT=str(self.output), GITHUB_STEP_SUMMARY=str(self.summary),
                        CALLS=str(self.calls), PR_FILE=str(self.pr), VERSION="2.3.0",
                        VERSIONS='[{"number": "2.2.0"}, {"number": "2.3.0"}]',
                        CURL_FAIL="0", PR_DENIED="0")
        self.mock("curl", 'if [ "$CURL_FAIL" = 1 ]; then exit 22; fi\nprintf "%s" "$VERSIONS"\n')
        self.mock("gem", 'echo "gem $*" >> "$CALLS"\n')
        self.mock("gh", '''echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "pr list") if [ -f "$PR_FILE" ]; then cat "$PR_FILE"; fi ;;
  "pr create") if [ "$PR_DENIED" = 1 ]; then exit 1; fi
    echo https://example.test/pr/1 > "$PR_FILE" ;;
  "release create") ;;
  *) exit 99 ;;
esac
''')
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Contract")
        self.git("config", "user.email", "contract@example.test")
        self.version("2.2.0")
        (self.repo / "README.md").write_text("initial\n")
        self.commit("base")
        self.git("tag", "v2.2.0")
        subprocess.run(["git", "init", "--bare", str(self.remote)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "origin", "main", "--tags")
        hook = self.remote / "hooks/pre-receive"
        hook.write_text('#!/bin/sh\nwhile read old new ref; do\n'
                        'if [ "$ref" = refs/heads/main ]; then echo GH013 >&2; exit 1; fi\ndone\n')
        hook.chmod(0o755)

    def mock(self, name, content):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + content)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env,
                                       stderr=subprocess.STDOUT, text=True).strip()

    def version(self, version):
        path = self.repo / "lib/omniauth-v2-ynab/version.rb"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('module OmniAuth\n  module YNAB\n    VERSION = "' + version + '".freeze\n  end\nend\n')

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-m", message)

    def run_step(self, name, success=True):
        script = STEPS[name]["run"].replace("${{ steps.version.outputs.version }}", self.env["VERSION"])
        result = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
                                cwd=self.repo, env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def publish(self):
        if self.outputs().get("publish") == "true":
            self.env["VERSION"] = self.outputs()["version"]
            for name in ["Build gem", "Push to RubyGems", "Tag release", "Create GitHub Release"]:
                self.run_step(name)

    def outputs(self):
        return dict(line.split("=", 1) for line in self.output.read_text().splitlines())

    def test_workflow_guards_and_permissions(self):
        job = WORKFLOW_DATA["jobs"]["release"]
        self.assertIn("github.event.workflow_run.event == 'push'", job["if"])
        self.assertEqual(WORKFLOW_DATA["permissions"], {"contents": "write", "id-token": "write"})
        for name in ["Build gem", "Configure RubyGems credentials (OIDC)", "Push to RubyGems",
                     "Tag release", "Create GitHub Release"]:
            self.assertEqual(STEPS[name]["if"], "steps.version.outputs.publish == 'true'")
        self.assertEqual(STEPS["Resolve version"]["if"], "steps.changes.outputs.release == 'true'")
        self.assertNotIn("HEAD:main", WORKFLOW.read_text())

    def test_bookkeeping_squash_and_merge_are_skipped(self):
        self.version("2.3.0")
        path = self.repo / ".github/workflows/release.yml"
        path.parent.mkdir(parents=True)
        path.write_text(WORKFLOW.read_text())
        self.commit("Repair release bookkeeping (#7)")
        self.run_step("Check release changes")
        self.assertEqual(self.outputs()["release"], "false")
        self.git("switch", "-c", "bookkeeping")
        self.version("2.4.0")
        self.commit("bookkeeping")
        self.git("switch", "main")
        self.git("merge", "--no-ff", "bookkeeping", "-m", "Merge pull request")
        self.run_step("Check release changes")
        self.assertEqual(self.outputs()["release"], "false")

    def test_real_changes_release(self):
        (self.repo / "README.md").write_text("changed\n")
        self.commit("normal change")
        self.run_step("Check release changes")
        self.assertEqual(self.outputs()["release"], "true")

    def test_multiple_commits_cannot_hide_real_changes(self):
        (self.repo / "README.md").write_text("real change before bookkeeping\n")
        self.commit("feature")
        self.version("2.3.0")
        self.commit("last commit only changes version")
        self.run_step("Check release changes")
        self.assertEqual(self.outputs()["release"], "true")

    def test_exact_released_source_is_skipped(self):
        self.run_step("Check release changes")
        self.assertEqual(self.outputs()["release"], "false")

    def test_published_candidate_skips_all_publication(self):
        self.run_step("Resolve version")
        self.assertEqual(self.outputs(), {"version": "2.3.0", "bumped": "true", "publish": "false"})
        self.publish()
        self.assertFalse(self.calls.exists())
        self.run_step("Propose version bookkeeping PR")
        first = self.git("ls-remote", "origin", "refs/heads/release/bookkeeping-v2.3.0")
        self.run_step("Propose version bookkeeping PR")
        self.assertEqual(first, self.git("ls-remote", "origin", "refs/heads/release/bookkeeping-v2.3.0"))
        calls = self.calls.read_text()
        self.assertEqual(calls.count("gh pr create"), 1)
        self.assertNotIn("gem push", calls)
        self.assertNotIn("release create", calls)
        self.assertEqual(self.git("ls-remote", "origin", "refs/heads/main").split()[0],
                         self.git("rev-parse", "main"))

    def test_new_candidate_and_manual_version(self):
        self.env["VERSIONS"] = '[{"number":"2.2.0"}]'
        self.run_step("Resolve version")
        self.assertEqual(self.outputs()["publish"], "true")
        self.assertEqual(self.outputs()["version"], "2.3.0")
        self.version("3.0.0")
        self.run_step("Resolve version")
        self.assertEqual(self.outputs(), {"version": "3.0.0", "bumped": "false", "publish": "true"})

    def test_fresh_publication_then_same_source_retry(self):
        self.env["VERSIONS"] = '[{"number":"2.2.0"}]'
        source = self.git("rev-parse", "HEAD")
        self.run_step("Resolve version")
        self.publish()
        self.assertEqual(self.calls.read_text().count("gem push"), 1)
        self.assertTrue(self.git("ls-remote", "origin", "refs/tags/v2.3.0"))
        self.git("restore", "--source=" + source, "--staged", "--worktree",
                 "lib/omniauth-v2-ynab/version.rb")
        self.run_step("Resolve version")
        self.publish()
        self.assertEqual(self.calls.read_text().count("gem push"), 1)
        self.assertEqual(self.calls.read_text().count("gh release create"), 1)

    def test_correct_next_minor_after_bookkeeping(self):
        self.version("2.3.0")
        self.run_step("Resolve version")
        self.assertEqual(self.outputs(), {"version": "2.4.0", "bumped": "true", "publish": "true"})

    def test_tag_alone_prevents_repeat_publication(self):
        self.env["VERSIONS"] = '[]'
        self.git("tag", "v2.3.0")
        self.run_step("Resolve version")
        self.assertEqual(self.outputs()["publish"], "false")

    def test_registry_failure_stops_before_publication(self):
        self.env["CURL_FAIL"] = "1"
        self.run_step("Resolve version", success=False)
        self.assertEqual(self.outputs(), {})
        self.assertFalse(self.calls.exists())

    def test_denied_pr_preserves_ready_branch(self):
        self.run_step("Resolve version")
        self.env["PR_DENIED"] = "1"
        result = self.run_step("Propose version bookkeeping PR", success=False)
        self.assertIn("GITHUB_TOKEN cannot create", result.stdout)
        self.assertIn("release/bookkeeping-v2.3.0", self.summary.read_text())
        self.assertTrue(self.git("ls-remote", "origin", "refs/heads/release/bookkeeping-v2.3.0"))

    def test_other_writer_branch_is_not_overwritten(self):
        self.git("switch", "-c", "other")
        self.version("9.0.0")
        self.commit("other writer")
        self.git("push", "origin", "HEAD:refs/heads/release/bookkeeping-v2.3.0")
        original = self.git("ls-remote", "origin", "refs/heads/release/bookkeeping-v2.3.0")
        self.git("switch", "main")
        self.run_step("Resolve version")
        self.run_step("Propose version bookkeeping PR", success=False)
        self.assertEqual(original, self.git("ls-remote", "origin", "refs/heads/release/bookkeeping-v2.3.0"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
