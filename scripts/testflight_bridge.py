#!/usr/bin/env python3
"""Protected GitHub job adapter; Xcode Cloud remains the build/delivery engine."""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

REPO = "amitsankaran1/Tyri"
OWNER = "amitsankaran1"
CONTROL_PR = 25
APP = "6757515805"
WORKFLOW = "37dfe861-29f0-4013-bc1c-5dc29544d23d"
GROUP = "ef128175-ca20-4e29-8e04-b0d222463e8d"
MAIN_REF = "c262f4c7-85ec-4786-9c77-9672cac0aa78"
SHA = re.compile(r"[0-9a-f]{40}")
COMMAND = re.compile(r"/tyri-build ([0-9a-f]{32}) ([0-9a-f]{40})")


def select_request(event_name, event, actor, repository):
    if repository != REPO:
        raise ValueError("This adapter is restricted to Tyri")
    if event_name == "issue_comment":
        comment = event.get("comment", {})
        match = COMMAND.fullmatch(comment.get("body", "").strip())
        if (actor != OWNER or comment.get("user", {}).get("login") != OWNER
                or event.get("action") != "created" or event.get("issue", {}).get("number") != CONTROL_PR
                or not event.get("issue", {}).get("pull_request") or not match):
            raise ValueError("Not an authorized Tyri build request")
        return {"request_id": f"comment-{comment['id']}", "task_id": match[1],
                "source_sha": match[2], "fresh": True}
    if event_name == "workflow_dispatch":
        inputs = event.get("inputs", {})
        if actor != OWNER or not re.fullmatch(r"[0-9a-f]{32}", inputs.get("request_id", "")):
            raise ValueError("Not an authorized manual request")
        sha = inputs.get("source_sha", "")
        if not SHA.fullmatch(sha):
            raise ValueError("An exact source revision is required")
        return {"request_id": "manual-" + inputs["request_id"], "source_sha": sha, "fresh": True}
    if event_name == "push" and event.get("ref") == "refs/heads/main" and not event.get("deleted"):
        sha = event.get("after", "")
        if not SHA.fullmatch(sha):
            raise ValueError("Invalid merged source revision")
        return {"request_id": "merge-" + sha, "source_sha": sha, "fresh": False}
    raise ValueError("Unsupported event")


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def der_to_raw(signature):
    # OpenSSL emits a short DER sequence of two unsigned P-256 integers.
    if len(signature) < 8 or signature[0] != 0x30 or signature[1] != len(signature) - 2:
        raise ValueError("Invalid ECDSA signature")
    pos, parts = 2, []
    for _ in range(2):
        if signature[pos] != 2:
            raise ValueError("Invalid ECDSA integer")
        size = signature[pos + 1]
        integer = signature[pos + 2:pos + 2 + size].lstrip(b"\0")
        if not integer or len(integer) > 32:
            raise ValueError("Invalid P-256 signature length")
        parts.append(integer.rjust(32, b"\0"))
        pos += size + 2
    if pos != len(signature):
        raise ValueError("Trailing signature data")
    return b"".join(parts)


def apple_jwt(key_path):
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now - 10,
              "exp": now + 600, "aud": "appstoreconnect-v1"}
    message = (b64(json.dumps(header).encode()) + "." + b64(json.dumps(claims).encode())).encode()
    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                            input=message, capture_output=True, check=True)
    return message.decode() + "." + b64(der_to_raw(result.stdout))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class API:
    def __init__(self, origin, token):
        self.origin, self.token = origin, token

    def call(self, method, path, data=None):
        if not path.startswith("/") or path.startswith("//"):
            raise ValueError("API path must remain on the configured origin")
        request = urllib.request.Request(self.origin + path,
            data=None if data is None else json.dumps(data).encode(), method=method,
            headers={"Authorization": "Bearer " + self.token(), "Accept": "application/json",
                     "Content-Type": "application/json", "User-Agent": "Tyri-delivery-adapter"})
        try:
            ca = "/etc/ssl/cert.pem" if Path("/etc/ssl/cert.pem").exists() else None
            with urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(
                    context=ssl.create_default_context(cafile=ca))).open(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Do not print response bodies or authorization material.
            raise RuntimeError(f"API {method} failed: HTTP {error.code}") from None


def find_receipt(github, request_id):
    marker = f"<!-- tyri-delivery:{request_id} -->"
    found = []
    for page in range(1, 101):
        comments = github.call("GET", f"/repos/{REPO}/issues/{CONTROL_PR}/comments?per_page=100&page={page}")
        for comment in comments:
            body = comment.get("body", "")
            if comment.get("user", {}).get("login") == "github-actions[bot]" and body.startswith(marker + "\n```json\n"):
                payload = body[len(marker + "\n```json\n"):].split("\n```", 1)[0]
                found.append((comment["id"], json.loads(payload)))
        if len(comments) < 100:
            break
    else:
        raise RuntimeError("Receipt lookup exceeded its bounded history; reconcile manually")
    if len(found) > 1:
        raise RuntimeError("Multiple receipts for one request; do not start another build")
    return found[0] if found else (None, None)


def save_receipt(github, request, receipt, comment_id):
    body = f"<!-- tyri-delivery:{request['request_id']} -->\n```json\n" + json.dumps(receipt, indent=2) + "\n```"
    if comment_id:
        github.call("PATCH", f"/repos/{REPO}/issues/comments/{comment_id}", {"body": body})
        return comment_id
    return github.call("POST", f"/repos/{REPO}/issues/{CONTROL_PR}/comments", {"body": body})["id"]


def timestamp(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def matching_runs(apple, sha, after=None):
    data = apple.call("GET", f"/v1/ciWorkflows/{WORKFLOW}/buildRuns?sort=-number&limit=200")["data"]
    return [run for run in data if (run["attributes"].get("sourceCommit") or {}).get("commitSha") == sha
            and (after is None or timestamp(run["attributes"]["createdDate"]) >= timestamp(after))]


def start_or_resume(apple, github, request):
    comment_id, receipt = find_receipt(github, request["request_id"])
    if receipt:
        if receipt["source_sha"] != request["source_sha"]:
            raise RuntimeError("Request source changed; reconcile instead of replacing it")
        if receipt.get("ci_run_id"):
            return comment_id, receipt
        # A prior job crossed the write boundary. Reconcile; never repeat POST blindly.
        candidates = matching_runs(apple, request["source_sha"], receipt["attempted_at"])
        if len(candidates) != 1:
            raise RuntimeError("Prior trigger outcome is uncertain; inspect Apple before a new request")
        receipt["ci_run_id"] = candidates[0]["id"]
    else:
        receipt = {**request, "app_id": APP, "workflow_id": WORKFLOW, "group_id": GROUP}
        if request["fresh"]:
            main = github.call("GET", f"/repos/{REPO}/git/ref/heads/main")["object"]["sha"]
            if main != request["source_sha"]:
                raise RuntimeError("Build-only requests must name current approved main")
            workflow = apple.call("GET", f"/v1/ciWorkflows/{WORKFLOW}")["data"]["attributes"]
            if not workflow.get("isEnabled"):
                raise RuntimeError("The approved delivery workflow is not activated")
            ref = apple.call("GET", f"/v1/scmGitReferences/{MAIN_REF}")["data"]["attributes"]
            if ref.get("canonicalName") != "refs/heads/main" or ref.get("kind") != "BRANCH":
                raise RuntimeError("The configured Apple reference is not main")
            receipt["attempted_at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
            comment_id = save_receipt(github, request, receipt, None)
            result = apple.call("POST", "/v1/ciBuildRuns", {"data": {"type": "ciBuildRuns",
                "attributes": {"clean": True}, "relationships": {
                    "workflow": {"data": {"type": "ciWorkflows", "id": WORKFLOW}},
                    "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": MAIN_REF}}}}})
            receipt["ci_run_id"] = result["data"]["id"]
        else:
            # The main merge triggers Xcode Cloud. This job only observes it.
            deadline = time.monotonic() + 300
            while True:
                candidates = matching_runs(apple, request["source_sha"])
                if len(candidates) == 1:
                    receipt["ci_run_id"] = candidates[0]["id"]
                    break
                if len(candidates) > 1 or time.monotonic() >= deadline:
                    raise RuntimeError("Automatic run missing or ambiguous; do not trigger a duplicate")
                time.sleep(20)
    comment_id = save_receipt(github, request, receipt, comment_id)
    return comment_id, receipt


def verify_once(apple, receipt):
    run = apple.call("GET", f"/v1/ciBuildRuns/{receipt['ci_run_id']}")["data"]["attributes"]
    receipt["cloud_build_number"] = run["number"]
    sha = (run.get("sourceCommit") or {}).get("commitSha")
    if sha and sha != receipt["source_sha"]:
        raise RuntimeError("Apple resolved a different source revision; do not certify delivery")
    if run["executionProgress"] != "COMPLETE":
        return False
    if run.get("completionStatus") != "SUCCEEDED":
        raise RuntimeError("Xcode Cloud run did not succeed")
    if sha != receipt["source_sha"]:
        raise RuntimeError("Successful run has no verifiable source revision")
    builds = apple.call("GET", f"/v1/ciBuildRuns/{receipt['ci_run_id']}/builds")["data"]
    if len(builds) != 1:
        raise RuntimeError("Expected exactly one Tyri app build")
    build, = builds
    app = apple.call("GET", f"/v1/builds/{build['id']}/app")["data"]
    if app["id"] != APP:
        raise RuntimeError("Unexpected app identity")
    attrs = build["attributes"]
    if attrs.get("expired") or attrs.get("processingState") in ("FAILED", "INVALID"):
        raise RuntimeError("Build expired or processing failed")
    if attrs.get("processingState") != "VALID":
        return False
    path, available = f"/v1/betaGroups/{GROUP}/builds?limit=200", False
    for _ in range(100):
        page = apple.call("GET", path)
        if any(item["id"] == build["id"] for item in page["data"]):
            available = True
            break
        next_url = page.get("links", {}).get("next")
        if not next_url:
            break
        parsed = urlsplit(next_url)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com":
            raise RuntimeError("Unexpected pagination origin")
        path = parsed.path + ("?" + parsed.query if parsed.query else "")
    if not available:
        return False
    version = apple.call("GET", f"/v1/builds/{build['id']}/preReleaseVersion")["data"]["attributes"]["version"]
    receipt.update(build_id=build["id"], version=version, build_number=attrs["version"],
                   processing="VALID", available_group="Amit Internal", verified_at=dt.datetime.now(dt.timezone.utc).isoformat())
    return True


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    request = select_request(os.environ["GITHUB_EVENT_NAME"], event, os.environ["GITHUB_ACTOR"], os.environ["GITHUB_REPOSITORY"])
    with tempfile.TemporaryDirectory(prefix="tyri-apple-key-") as temp:
        key = Path(temp) / "key.p8"
        private_key = os.environ["ASC_PRIVATE_KEY"]
        if not private_key.startswith("-----BEGIN PRIVATE KEY-----"):
            raise RuntimeError("The protected Apple API credential is not configured")
        key.write_text(private_key)
        key.chmod(0o600)
        apple_jwt(key)  # Validate auth configuration before any durable trigger receipt.
        apple = API("https://api.appstoreconnect.apple.com", lambda: apple_jwt(key))
        github = API("https://api.github.com", lambda: os.environ["GITHUB_TOKEN"])
        comment_id, receipt = start_or_resume(apple, github, request)
        deadline = time.monotonic() + 80 * 60
        while True:
            if verify_once(apple, receipt):
                save_receipt(github, request, receipt, comment_id)
                Path("delivery-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
                print(json.dumps(receipt))
                return
            if time.monotonic() >= deadline:
                raise RuntimeError("Delivery still pending; resume the recorded run, not a new upload")
            time.sleep(30)


if __name__ == "__main__":
    main()
