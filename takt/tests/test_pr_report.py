"""Tests for bin/takt-pr-report (copies the final summary into the PR body).

A fake `gh` on PATH serves PR states and bodies from a JSON file and records
the bodies written with `gh pr edit`.
"""
import json
import os
import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "bin" / "takt-pr-report"

FAKE_GH = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json, os, sys
    state = os.environ["FAKE_GH_STATE"]
    prs = json.load(open(state))
    args = sys.argv[1:]
    url = args[2]
    if args[:2] == ["pr", "view"]:
        print(json.dumps(prs[url]))
    elif args[:2] == ["pr", "edit"]:
        prs[url]["body"] = sys.stdin.read()
        prs[url]["edits"] = prs[url].get("edits", 0) + 1
        json.dump(prs, open(state, "w"))
    else:
        sys.exit(2)
    """
)


class PrReport(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        self.project = self.home / "proj"
        (self.project / ".takt").mkdir(parents=True)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "gh").write_text(FAKE_GH)
        (bin_dir / "gh").chmod(0o755)
        self.state = self.tmp / "prs.json"
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "HOME": str(self.home),
            "FAKE_GH_STATE": str(self.state),
        }
        self.tasks = []
        self.prs = {}

    def add_task(self, name, state="OPEN", body="Workflow done.\n\n<!-- takt:managed -->", summary="# 最終検証サマリー\n"):
        worktree = self.tmp / "wt" / name
        url = f"https://github.com/o/r/pull/{len(self.tasks) + 1}"
        reports = worktree / ".takt" / "runs" / f"run-{name}" / "reports"
        if summary is not None:
            old = reports / "subworkflows" / "a" / "summary.md"
            old.parent.mkdir(parents=True)
            old.write_text("old summary")
            os.utime(old, (time.time() - 100, time.time() - 100))
            new = reports / "subworkflows" / "b" / "summary.md"
            new.parent.mkdir(parents=True)
            new.write_text(summary.replace("WT", str(worktree)).replace("HOME", str(self.home)))
            internal = reports / ".takt-report-internal" / "summary.md"
            internal.parent.mkdir(parents=True)
            internal.write_text("internal copy")
        self.tasks.append(
            {"name": name, "status": "completed", "pr_url": url, "worktree_path": str(worktree), "run_slug": f"run-{name}"}
        )
        self.prs[url] = {"state": state, "body": body}
        return url

    def run_script(self, *args):
        import yaml

        (self.project / ".takt" / "tasks.yaml").write_text(yaml.safe_dump({"tasks": self.tasks}))
        self.state.write_text(json.dumps(self.prs))
        result = subprocess.run(
            [str(SCRIPT), str(self.project), *args], env=self.env, capture_output=True, text=True
        )
        self.prs = json.loads(self.state.read_text())
        return result

    def test_puts_the_newest_summary_before_the_managed_marker(self):
        url = self.add_task("a", summary="# 最終検証サマリー\n\n## 最終レポート\n- x\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        body = self.prs[url]["body"]
        self.assertIn("## 最終レポート", body)
        self.assertNotIn("old summary", body)
        self.assertNotIn("internal copy", body)
        self.assertTrue(body.rstrip().endswith("<!-- takt:managed -->"))
        self.assertLess(body.index("Workflow done."), body.index("<!-- takt:final-report -->"))

    def test_runs_once(self):
        url = self.add_task("a")
        self.run_script()
        self.run_script()
        self.assertEqual(self.prs[url]["edits"], 1)

    def test_skips_closed_prs_tasks_without_a_summary_and_unfinished_tasks(self):
        merged = self.add_task("merged", state="MERGED")
        missing = self.add_task("missing", summary=None)
        pending = self.add_task("pending")
        self.tasks[-1]["status"] = "running"
        self.run_script()
        for url in (merged, missing, pending):
            self.assertNotIn("edits", self.prs[url])

    def test_writes_no_local_paths(self):
        url = self.add_task("a", summary="see WT/service/app/page.tsx:3 and HOME/x\n")
        self.run_script()
        body = self.prs[url]["body"]
        self.assertIn("see service/app/page.tsx:3 and ~/x", body)
        self.assertNotIn(str(self.tmp), body)

    def test_cuts_a_summary_that_would_exceed_the_body_limit(self):
        url = self.add_task("a", summary="x" * 70000)
        self.run_script()
        body = self.prs[url]["body"]
        self.assertLess(len(body), 65536)
        self.assertIn("長すぎるため", body)

    def test_dry_run_prints_and_does_not_edit(self):
        url = self.add_task("a")
        result = self.run_script("--dry-run")
        self.assertIn("takt:final-report", result.stdout)
        self.assertNotIn("edits", self.prs[url])

    def test_no_tasks_file_is_not_an_error(self):
        result = subprocess.run([str(SCRIPT), str(self.tmp)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
