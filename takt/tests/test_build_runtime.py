"""Tests for takt/build-runtime.py.

    python3 -m unittest discover -s takt/tests -p 'test_*.py'

Checks the real takt/common, takt/work and takt/private files, and (when TAKT
is installed) that TAKT's own validator accepts the generated runtime.yaml.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

TAKT_DIR = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_runtime", TAKT_DIR / "build-runtime.py")
build_runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_runtime)

DENY = ["opencode", "openrouter"]


def generated(env: str, deny=(), root: Path = TAKT_DIR) -> dict:
    return yaml.safe_load(build_runtime.build(env, list(deny), root))


def providers_of(doc: dict) -> set[str]:
    return {p["provider"] for p in doc["provider"]["profiles"].values()}


def strip_assignment(entry: dict, assignment: str) -> dict:
    def name(n):
        return n.removesuffix(f"@{assignment}")

    if "profile" in entry:
        return {"profile": name(entry["profile"])}
    return {"ladder": [name(n) for n in entry["ladder"]]}


class WorkEnvironment(unittest.TestCase):
    def test_builds_with_private_providers_denied(self):
        doc = generated("work", DENY)
        self.assertEqual(providers_of(doc), {"claude-sdk", "codex"})
        self.assertNotIn("assignments", doc["provider"])

    def test_text_has_no_private_provider_or_endpoint(self):
        text = build_runtime.build("work", DENY)
        for word in ("opencode", "openrouter", "base_url", "api_key"):
            self.assertNotIn(word, text)

    def test_codex_plays_the_implementer_roles(self):
        doc = generated("work", DENY)
        profiles = doc["provider"]["profiles"]
        targets = doc["provider"]["targets"]
        self.assertEqual(profiles[targets["personas"]["coder"]["profile"]]["provider"], "codex")
        for step in ("reimplement", "fix-retry"):
            self.assertEqual(profiles[targets["steps"][step]["profile"]]["provider"], "codex")
        self.assertEqual(profiles[targets["steps"]["write_tests"]["profile"]]["provider"], "claude-sdk")

    def test_planner_ladder_stays_on_opus(self):
        doc = generated("work", DENY)
        ladder = doc["provider"]["targets"]["personas"]["planner"]["ladder"]
        models = [doc["provider"]["profiles"][n]["model"] for n in ladder]
        self.assertEqual(models, ["opus", "opus"])

    def test_selector_runs_on_haiku_and_final_gate_on_opus(self):
        for env, deny in (("work", DENY), ("private", ())):
            provider = generated(env, deny)["provider"]
            profiles, targets = provider["profiles"], provider["targets"]
            selector = targets["internal_agents"]["selector"]["profile"]
            self.assertEqual(profiles[selector]["model"], "haiku", env)
            # The final gate is routed by its persona, not by step name: when
            # adjudication is skipped it is the only judge-model check left.
            self.assertNotIn("final-gate", targets["steps"], env)
            self.assertNotIn("final-gate-direct", targets["steps"], env)
            supervisor = targets["personas"]["supervisor"]["profile"]
            self.assertEqual(profiles[supervisor]["model"], "opus", env)
            # The review that found real problems stays on the judgment model.
            arch = targets["steps"]["architecture-review"]["profile"]
            self.assertEqual(profiles[arch]["model"], "opus", env)

    def test_no_profile_uses_fable(self):
        # Fable is kept out of TAKT workflows: top-model judgment happens when
        # the job is written, before TAKT runs.
        for env, deny in (("work", DENY), ("private", ())):
            profiles = generated(env, deny)["provider"]["profiles"]
            for name, spec in profiles.items():
                self.assertNotIn("fable", spec["model"], f"{env}: {name}")

    def test_plan_review_and_the_revised_plan_run_on_opus(self):
        for env, deny in (("work", DENY), ("private", ())):
            provider = generated(env, deny)["provider"]
            steps = provider["targets"]["steps"]
            model = lambda step: provider["profiles"][steps[step]["profile"]]["model"]
            self.assertEqual(model("plan-review"), "opus", env)
            self.assertEqual(model("plan-review-2"), "opus", env)
            self.assertEqual(model("plan-revise"), "opus", env)


class PrivateEnvironment(unittest.TestCase):
    def test_default_assignment_is_claude_only(self):
        doc = generated("private")
        provider = doc["provider"]
        used = {provider["defaults"]["profile"]}
        for kind in provider["targets"].values():
            for entry in kind.values():
                used.update(entry.get("ladder", [entry.get("profile")]))
        self.assertEqual({provider["profiles"][n]["provider"] for n in used}, {"claude-sdk"})

    def test_credit_out_moves_exactly_the_codex_roles_of_work_to_opencode(self):
        work = generated("work", DENY)["provider"]
        private = generated("private")["provider"]
        credit_out = private["assignments"]["credit-out"]
        work_profiles = work["profiles"]
        private_profiles = private["profiles"]

        def flat(targets):
            return {(kind, name): entry for kind, entries in targets.items() for name, entry in entries.items()}

        work_targets = flat(work["targets"])
        credit_targets = flat(credit_out["targets"])
        self.assertEqual(set(work_targets), set(credit_targets))
        for key, entry in credit_targets.items():
            names = entry.get("ladder", [entry.get("profile")])
            work_names = work_targets[key].get("ladder", [work_targets[key].get("profile")])
            work_is_codex = any(work_profiles[n]["provider"] == "codex" for n in work_names)
            private_is_opencode = any(private_profiles[n]["provider"] == "opencode" for n in names)
            self.assertEqual(work_is_codex, private_is_opencode, key)
            # Same role table: only the assignment suffix differs.
            self.assertEqual(strip_assignment(entry, "credit-out"), work_targets[key], key)

    def test_go_out_gives_the_codex_roles_of_work_to_the_same_codex_models(self):
        work = generated("work", DENY)["provider"]
        private = generated("private")["provider"]
        go_out = private["assignments"]["go-out"]
        overridden = {n.split("@")[0] for n in private["profiles"] if n.endswith("@go-out")}
        work_codex = {n for n, p in work["profiles"].items() if p["provider"] == "codex"}
        self.assertEqual(overridden, work_codex)
        for role in work_codex:
            self.assertEqual(private["profiles"][f"{role}@go-out"], work["profiles"][role], role)
        default = go_out["defaults"]["profile"]
        self.assertEqual(private["profiles"][default]["provider"], "claude-sdk")
        used = set()
        for kind in go_out["targets"].values():
            for entry in kind.values():
                used.update(entry.get("ladder", [entry.get("profile")]))
        self.assertNotIn("opencode", {private["profiles"][n]["provider"] for n in used})

    def test_credit_out_keeps_defaults_on_claude(self):
        private = generated("private")["provider"]
        default = private["assignments"]["credit-out"]["defaults"]["profile"]
        self.assertEqual(private["profiles"][default]["provider"], "claude-sdk")


class Errors(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        shutil.copytree(TAKT_DIR / "common", self.root / "common")
        shutil.copytree(TAKT_DIR / "work", self.root / "work")
        shutil.copytree(TAKT_DIR / "private", self.root / "private")

    def edit(self, rel: str, fn):
        path = self.root / rel
        data = yaml.safe_load(path.read_text())
        fn(data)
        path.write_text(yaml.safe_dump(data))

    def test_deny_rejects_an_opencode_profile_in_work(self):
        self.edit("work/profiles.yaml", lambda d: d["roles"].update(worker={"provider": "opencode", "model": "opencode-go/x"}))
        with self.assertRaisesRegex(build_runtime.BuildError, "denied provider 'opencode'"):
            build_runtime.build("work", DENY, self.root)

    def test_deny_rejects_an_openrouter_model_id(self):
        self.edit("work/profiles.yaml", lambda d: d["roles"].update(worker={"provider": "claude-sdk", "model": "openrouter/x"}))
        with self.assertRaisesRegex(build_runtime.BuildError, "denied provider 'openrouter'"):
            build_runtime.build("work", DENY, self.root)

    def test_deny_rejects_base_url_options(self):
        self.edit("work/profiles.yaml", lambda d: d["roles"]["worker"].update(options={"base_url": "https://x"}))
        with self.assertRaisesRegex(build_runtime.BuildError, "base_url"):
            build_runtime.build("work", DENY, self.root)

    def test_role_missing_from_an_environment_fails(self):
        self.edit("work/profiles.yaml", lambda d: d["roles"].pop("judge"))
        with self.assertRaisesRegex(build_runtime.BuildError, "roles not defined: judge"):
            build_runtime.build("work", DENY, self.root)

    def test_internal_agent_with_a_ladder_fails(self):
        self.edit("common/targets.yaml", lambda d: d["internal_agents"].update(selector={"ladder": ["router", "worker"]}))
        with self.assertRaisesRegex(build_runtime.BuildError, "takes a role name"):
            build_runtime.build("work", DENY, self.root)

    def test_assignment_overriding_an_unknown_role_fails(self):
        self.edit("private/profiles.yaml", lambda d: d["assignments"]["credit-out"].update(nobody={"provider": "opencode", "model": "m"}))
        with self.assertRaisesRegex(build_runtime.BuildError, "unknown roles: nobody"):
            build_runtime.build("private", [], self.root)


def installed_takt() -> Path | None:
    exe = shutil.which("takt", path="/opt/homebrew/bin:/usr/local/bin")
    if not exe:
        return None
    pkg = Path(exe).resolve().parents[1]
    return pkg if (pkg / "dist" / "infra" / "config" / "runtime-provider" / "policy.js").exists() else None


@unittest.skipUnless(installed_takt() and shutil.which("node"), "TAKT or node not installed")
class AcceptedByTakt(unittest.TestCase):
    def check(self, env: str, deny):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "runtime.yaml"
            path.write_text(build_runtime.build(env, list(deny)))
            result = subprocess.run(
                ["node", str(Path(__file__).with_name("validate-runtime.mjs")), str(installed_takt()), str(path)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_work(self):
        self.assertIn("ok default", self.check("work", DENY))

    def test_private_with_credit_out(self):
        out = self.check("private", [])
        self.assertIn("ok default", out)
        self.assertIn("ok credit-out", out)
        self.assertIn("ok go-out", out)


if __name__ == "__main__":
    unittest.main()
