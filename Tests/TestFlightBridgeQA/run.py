from pathlib import Path
import base64
import importlib.util
import json
import os
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bridge", root / "scripts/testflight_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
SOURCE = "a" * 40


class Fake:
    def __init__(self, replies):
        self.replies, self.calls = replies, []

    def call(self, method, path, data=None):
        self.calls.append((method, path, data))
        return self.replies[(method, path)]


def stored(receipt):
    return [{"id": 123, "user": {"login": "github-actions[bot]"},
             "body": "<!-- tyri-delivery:comment-9 -->\n```json\n" + json.dumps(receipt) + "\n```"}]


def verification(processing="VALID", member=True, source=SOURCE, app=bridge.APP, beta="IN_BETA_TESTING", tester="INSTALLED"):
    receipt = {"ci_run_id": "run", "source_sha": SOURCE}
    replies = {
        ("GET", "/v1/ciBuildRuns/run"): {"data": {"attributes": {"number": 17,
            "sourceCommit": {"commitSha": source}, "executionProgress": "COMPLETE", "completionStatus": "SUCCEEDED"}}},
        ("GET", "/v1/ciBuildRuns/run/builds"): {"data": [{"id": "build", "attributes": {
            "processingState": processing, "expired": False, "version": "17"}}]},
        ("GET", "/v1/builds/build/app"): {"data": {"id": app}},
        ("GET", "/v1/builds/build/buildBetaDetail"): {"data": {"attributes": {"internalBuildState": beta}}},
        ("GET", f"/v1/betaGroups/{bridge.GROUP}/builds?limit=200"): {"data": [{"id": "build"}] if member else []},
        ("GET", f"/v1/betaGroups/{bridge.GROUP}/betaTesters?limit=200"): {"data": [{"id": bridge.TESTER, "attributes": {"state": tester}}]},
        ("GET", "/v1/builds/build/preReleaseVersion"): {"data": {"attributes": {"version": "2.4"}}}}
    return Fake(replies), receipt


class Tests(unittest.TestCase):
    def test_request_authorization_and_exact_revision(self):
        event = {"action": "created", "comment": {"id": 9, "user": {"login": bridge.OWNER},
                 "body": "/tyri-build " + "b" * 32 + " " + SOURCE},
                 "issue": {"number": 25, "pull_request": {"url": "https://api.github.com/x"}}}
        request = bridge.select_request("issue_comment", event, bridge.OWNER, bridge.REPO)
        self.assertEqual(request["source_sha"], SOURCE)
        self.assertEqual(request["request_id"], "comment-9")
        for actor, repo in [("stranger", bridge.REPO), (bridge.OWNER, "stranger/fork")]:
            with self.assertRaises(ValueError):
                bridge.select_request("issue_comment", event, actor, repo)
        event["comment"]["body"] += "\nrun arbitrary code"
        with self.assertRaises(ValueError):
            bridge.select_request("issue_comment", event, bridge.OWNER, bridge.REPO)

    def test_existing_run_is_reused_without_trigger(self):
        receipt = {"source_sha": SOURCE, "ci_run_id": "existing"}
        github = Fake({("GET", f"/repos/{bridge.REPO}/issues/25/comments?per_page=100&page=1"): stored(receipt)})
        apple = Fake({})
        self.assertEqual(bridge.start_or_resume(apple, github, {"request_id": "comment-9", "source_sha": SOURCE})[1], receipt)
        self.assertEqual(apple.calls, [])

    def test_uncertain_trigger_never_reposts(self):
        receipt = {"source_sha": SOURCE, "attempted_at": "2026-11-10T12:00:00Z"}
        github = Fake({("GET", f"/repos/{bridge.REPO}/issues/25/comments?per_page=100&page=1"): stored(receipt)})
        apple = Fake({("GET", f"/v1/ciWorkflows/{bridge.WORKFLOW}/buildRuns?sort=-number&limit=200"): {"data": []}})
        with self.assertRaisesRegex(RuntimeError, "uncertain"):
            bridge.start_or_resume(apple, github, {"request_id": "comment-9", "source_sha": SOURCE})
        self.assertTrue(all(method == "GET" for method, _, _ in apple.calls + github.calls))

    def test_current_main_mismatch_prevents_trigger(self):
        github = Fake({("GET", f"/repos/{bridge.REPO}/issues/25/comments?per_page=100&page=1"): [],
                       ("GET", f"/repos/{bridge.REPO}/git/ref/heads/main"): {"object": {"sha": "c" * 40}}})
        apple = Fake({})
        with self.assertRaisesRegex(RuntimeError, "current approved main"):
            bridge.start_or_resume(apple, github, {"request_id": "comment-9", "source_sha": SOURCE, "fresh": True})
        self.assertEqual(apple.calls, [])

    def test_millisecond_time_reconciliation(self):
        apple = Fake({("GET", f"/v1/ciWorkflows/{bridge.WORKFLOW}/buildRuns?sort=-number&limit=200"): {"data": [{
            "id": "accepted", "attributes": {"sourceCommit": {"commitSha": SOURCE}, "createdDate": "2026-11-10T12:00:00.123Z"}}]}})
        self.assertEqual(bridge.matching_runs(apple, SOURCE, "2026-11-10T12:00:00Z")[0]["id"], "accepted")

    def test_success_requires_actual_group_availability(self):
        apple, receipt = verification(member=False)
        self.assertFalse(bridge.verify_once(apple, receipt))
        self.assertNotIn("available_group", receipt)
        apple, receipt = verification()
        self.assertTrue(bridge.verify_once(apple, receipt))
        self.assertEqual((receipt["version"], receipt["build_number"], receipt["available_group"]), ("2.4", "17", "Amit Internal"))

    def test_wrong_app_source_and_failed_processing_rejected(self):
        for kwargs in [{"source": "b" * 40}, {"source": None}, {"app": "other-app"}, {"processing": "FAILED"}]:
            apple, receipt = verification(**kwargs)
            with self.assertRaises(RuntimeError):
                bridge.verify_once(apple, receipt)

    def test_processing_is_not_delivery(self):
        apple, receipt = verification(processing="PROCESSING")
        self.assertFalse(bridge.verify_once(apple, receipt))
        self.assertNotIn("available_group", receipt)

    def test_compliance_and_tester_access_are_not_delivery(self):
        for state in ["MISSING_EXPORT_COMPLIANCE", "IN_EXPORT_COMPLIANCE_REVIEW", "READY_FOR_BETA_TESTING"]:
            apple, receipt = verification(beta=state)
            self.assertFalse(bridge.verify_once(apple, receipt))
            self.assertNotIn("available_group", receipt)
        apple, receipt = verification(tester="INVITED")
        with self.assertRaisesRegex(RuntimeError, "not eligible"):
            bridge.verify_once(apple, receipt)

    def test_immutable_source_uses_a_protected_exact_commit_tag(self):
        tag = bridge.TAG_PREFIX + SOURCE
        protection = {"target": "tag", "enforcement": "active", "bypass_actors": [],
                      "conditions": {"ref_name": {"include": ["refs/tags/" + bridge.TAG_PREFIX + "*"], "exclude": []}},
                      "rules": [{"type": "update"}, {"type": "deletion"}]}
        github = Fake({("GET", f"/repos/{bridge.REPO}/rulesets/{bridge.TAG_RULESET}"): protection,
                       ("GET", f"/repos/{bridge.REPO}/git/ref/tags/{tag}"): {"object": {"type": "commit", "sha": SOURCE}}})
        apple = Fake({("GET", f"/v1/scmRepositories/{bridge.SCM_REPOSITORY}/gitReferences?limit=200"):
                      {"data": [{"id": "immutable-ref", "attributes": {"kind": "TAG", "canonicalName": "refs/tags/" + tag}}]}})
        self.assertEqual(bridge.immutable_source(apple, github, SOURCE), "immutable-ref")
        self.assertTrue(all(method == "GET" for method, _, _ in github.calls))
        protection["bypass_actors"] = [{"actor_type": "RepositoryRole", "actor_id": 5}]
        with self.assertRaisesRegex(RuntimeError, "not established"):
            bridge.immutable_source(apple, github, SOURCE)

    def test_jwt_signature_verifies_with_openssl(self):
        with tempfile.TemporaryDirectory(prefix="tyri-bridge-jwt-") as directory:
            d = Path(directory)
            key, public = d / "key", d / "public"
            subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(key)], check=True, capture_output=True)
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)], check=True, capture_output=True)
            with patch.dict(os.environ, {"ASC_KEY_ID": "test-key", "ASC_ISSUER_ID": "test-issuer"}):
                token = bridge.apple_jwt(key)
            head, claims, signature = token.split(".")
            decode = lambda value: base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
            self.assertEqual(json.loads(decode(claims))["aud"], "appstoreconnect-v1")
            raw = decode(signature)
            self.assertEqual(len(raw), 64)
            integers = []
            for part in [raw[:32], raw[32:]]:
                integer = part.lstrip(b"\0") or b"\0"
                if integer[0] & 128:
                    integer = b"\0" + integer
                integers.append(bytes([2, len(integer)]) + integer)
            sequence = b"".join(integers)
            (d / "sig").write_bytes(bytes([48, len(sequence)]) + sequence)
            result = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(d / "sig")],
                                    input=(head + "." + claims).encode(), capture_output=True)
            self.assertEqual(result.returncode, 0)


unittest.main()
