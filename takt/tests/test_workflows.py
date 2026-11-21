"""Tests for the shape of the shared workflows in takt/common/workflows.

    python3 -m unittest discover -s takt/tests -p 'test_*.py'

The workflows are loaded with TAKT's own loader (tests/dump-workflow.mjs), so
the checks see what TAKT sees. Skipped when TAKT or node is not installed.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

TAKT_DIR = Path(__file__).resolve().parents[1]
WORKFLOWS = TAKT_DIR / "common" / "workflows"


def installed_takt() -> Path | None:
    exe = shutil.which("takt", path="/opt/homebrew/bin:/usr/local/bin")
    if not exe:
        return None
    pkg = Path(exe).resolve().parents[1]
    return pkg if (pkg / "dist" / "infra" / "config" / "loaders" / "workflowResolver.js").exists() else None


def load(name: str) -> dict:
    result = subprocess.run(
        ["node", str(Path(__file__).with_name("dump-workflow.mjs")), str(installed_takt()), str(WORKFLOWS / f"{name}.yaml")],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def step(workflow: dict, name: str) -> dict:
    return next(s for s in workflow["steps"] if s["name"] == name)


@unittest.skipUnless(installed_takt() and shutil.which("node"), "TAKT or node not installed")
class PlanReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = load("agora-development-core")

    def test_plan_goes_through_the_review_before_tests(self):
        self.assertEqual(step(self.core, "plan")["next"], ["plan-review", "COMPLETE", "ABORT"])
        self.assertEqual(step(self.core, "plan-review")["next"], ["write_tests", "plan-revise", "ABORT"])

    def test_at_most_one_send_back(self):
        self.assertEqual(step(self.core, "plan-revise")["next"], ["plan-review-2", "ABORT"])
        # The second review cannot send the plan back again.
        self.assertEqual(step(self.core, "plan-review-2")["next"], ["write_tests", "ABORT"])

    def test_plan_climbs_the_ladder_on_its_second_visit(self):
        self.assertEqual(step(self.core, "plan")["promotion"], [{"at": 2}])

    def test_review_steps_are_routed_by_step_name(self):
        targets = yaml.safe_load((TAKT_DIR / "common" / "targets.yaml").read_text())["steps"]
        self.assertEqual(targets["plan-review"], "judge")
        self.assertEqual(targets["plan-review-2"], "judge")
        self.assertEqual(targets["plan-revise"], "planner-top")

    def test_peer_review_is_the_capped_fork(self):
        self.assertEqual(step(self.core, "peer-review")["call"], "./agora-peer-review.yaml")


@unittest.skipUnless(installed_takt() and shutil.which("node"), "TAKT or node not installed")
class FixRoundCap(unittest.TestCase):
    def test_single_monitor_that_can_only_stop(self):
        monitors = load("agora-peer-review")["loopMonitors"]
        self.assertEqual(len(monitors), 1)
        monitor = monitors[0]
        self.assertEqual(monitor["cycle"], ["reviewers", "review-adjudication", "remediation"])
        self.assertEqual(monitor["ignoreSteps"], ["final-gate"])
        self.assertEqual(monitor["threshold"], 2)
        self.assertEqual(monitor["next"], ["ABORT"])


@unittest.skipUnless(installed_takt() and shutil.which("node"), "TAKT or node not installed")
class Callers(unittest.TestCase):
    def check(self, workflow: dict):
        calls = [s for s in workflow["steps"] if s["kind"] == "workflow_call"]
        core_calls = [s for s in calls if s["call"] == "./agora-development-core.yaml"]
        self.assertTrue(core_calls)
        self.assertNotIn("development-core", [s["call"] for s in calls])
        for call in core_calls:
            self.assertIn("agora-review-scope", call["args"]["review_policy_additions"], call["name"])
            self.assertIn("agora-fix-verification-scope", call["args"]["verification_policy"], call["name"])

    def test_agora_default(self):
        self.check(load("agora-default"))

    def test_agora_design_flow(self):
        self.check(load("agora-design-flow"))


if __name__ == "__main__":
    unittest.main()
