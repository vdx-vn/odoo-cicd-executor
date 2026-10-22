"""Private SCA tests on a public executor: emit only numeric summaries."""
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request

TEMPLATE_SHA = "020c1869444e708c31711816a80587f255e27b0b"
IMAGE = "registry.vdx.vn/sungroup/sca-pytest@sha256:d8fd02d8f0ae68bc56dbecf9312e64ad2639bac7deaddc15dde06aa9e9ea642c"


def run(command, env, log, cwd=None, input=None):
    result = subprocess.run(command, env=env, cwd=cwd, input=input, stdout=log, stderr=log)
    if result.returncode:
        raise RuntimeError("private execution failed")


def fetch(url, sha, target, username, password, env, log):
    clean = dict(env, FETCH_USER=username, FETCH_PASSWORD=password,
                 GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
                 GIT_CONFIG_COUNT="0", GIT_TERMINAL_PROMPT="0", GIT_TRACE="0",
                 GIT_TRACE_CURL="0")
    run(["git", "init", "-q", str(target)], clean, log)
    run(["git", "-C", str(target), "-c", "credential.helper=", "-c",
         'credential.helper=!f() { printf "%s\\n" "username=$FETCH_USER" "password=$FETCH_PASSWORD"; }; f',
         "fetch", "--quiet", "--depth", "1", url, sha], clean, log)
    run(["git", "-C", str(target), "checkout", "--quiet", "--detach", "FETCH_HEAD"], clean, log)
    head = subprocess.check_output(["git", "-C", str(target), "rev-parse", "HEAD"], env=clean, stderr=log).decode().strip()
    if head != sha:
        raise RuntimeError("revision mismatch")


def summary(text):
    # Never print test identifiers, traceback, source lines or arbitrary log text.
    matches = re.findall(r"(\d+) (passed|failed|skipped|errors?|xfailed|xpassed)\b", text)
    result = {}
    for number, kind in matches:
        result[kind] = int(number)
    return result


def main():
    sha = os.environ.get("SOURCE_SHA", "")
    request = os.environ.get("REQUEST_ID", "")
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or not re.fullmatch(r"67-[0-9]+-[0-9]+", request):
        print("Rejected invalid request")
        return 2
    print("project=67 commit=" + sha + " request=" + request)
    phase = "prepare"
    result = 1
    with tempfile.TemporaryDirectory(prefix="sca-test-") as temporary:
        root = Path(temporary)
        env = {k: os.environ[k] for k in ["PATH", "HOME", "LANG"] if k in os.environ}
        env.update(DOCKER_CONFIG=str(root / "docker-auth"), GIT_TERMINAL_PROMPT="0")
        Path(env["DOCKER_CONFIG"]).mkdir(mode=0o700)
        source = root / "source"
        template = source / ".gitlab-cicd"
        with (root / "private.log").open("wb") as log:
            try:
                fetch("https://gitlab.vdx.vn/chuonglm/sca-chuonglm.git", sha, source,
                      os.environ["SOURCE_USER"], os.environ["SOURCE_TOKEN"], env, log)
                fetch("https://gitlab.vdx.vn/infra/cicd-pipeline-template.git", TEMPLATE_SHA, template,
                      os.environ["TEMPLATE_USER"], os.environ["TEMPLATE_TOKEN"], env, log)
                phase = "registry"
                run(["docker", "login", "registry.vdx.vn", "--username", os.environ["REGISTRY_USER"],
                     "--password-stdin"], env, log, input=os.environ["REGISTRY_PASSWORD"].encode())
                env.update(CI_PROJECT_DIR=str(source), CI_PROJECT_ID="67", CI_COMMIT_BRANCH="dev",
                           CI_COMMIT_SHA=sha, CI_JOB_ID=os.environ["GITHUB_RUN_ID"],
                           CICD_SCRIPTS_PATH=str(template / "scripts"),
                           CICD_UTILS_SCRIPTS_PATH=str(template / "scripts/utils.sh"),
                           DOCKER_FOLDER=str(template / "config/odoo"),
                           ODOO_CONFIG_FILE=str(template / "config/odoo/etc/odoo.conf"),
                           ODOO_LOG_FILE_HOST=str(template / "config/odoo/logs/odoo.log"),
                           ODOO_ADDONS_PATH=str(source / "sources/extra-addons"),
                           ODOO_TEST_DATABASE_NAME="odoo_test", ODOO_PYTEST_DATABASE_NAME="odoo_test_pytest",
                           ODOO_PYTEST_IMAGE_TAG=IMAGE, ODOO_PYTEST_WORKERS="4",
                           ODOO_PYTEST_USE_PREBUILT_BASE="true", ODOO_PYTEST_ENABLE_HTTP="true",
                           ODOO_PYTEST_SNAPSHOT_MODE="off", ODOO_PYTEST_SNAPSHOT_EXPORT="false",
                           ODOO_PYTEST_SNAPSHOT_REPOSITORY="", ODOO_PYTEST_BASE_BUNDLE="/opt/pytest-base",
                           ODOO_XDIST_HTTP_PORT_BASE="18069", DB_IMAGE_TAG="postgres:17", IGNORE_TEST="")
                phase = "pytest"
                run(["bash", str(template / "scripts/run-parallel-odoo-test.sh")], env, log, cwd=source)
                result = 0
            except Exception:
                # Deliberately do not print exception text: it can contain private data.
                result = 1
            finally:
                if (template / "scripts/utils.sh").is_file():
                    subprocess.run(["bash", "-c", 'source "$CICD_UTILS_SCRIPTS_PATH"; cleanup_job_resources'],
                                   env=env, cwd=source, stdout=log, stderr=log)
        test_log = source / "parallel-odoo-test.log"
        counts = summary(test_log.read_text(errors="replace")) if test_log.is_file() else {}
        print(json.dumps({"phase": phase, "status": "success" if result == 0 else "failure", "counts": counts}))
    return result


if __name__ == "__main__":
    raise SystemExit(main())
