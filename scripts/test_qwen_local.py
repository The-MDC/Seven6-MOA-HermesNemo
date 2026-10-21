"""Tests for scripts/qwen-local-fetch.sh and scripts/qwen-local-serve.sh.

Neither script can be run for real in CI: one pulls 34 GB, the other needs a CUDA build of
llama.cpp. So the tests run them as a user would, against stand-ins:

  * a fake `curl` and tiny files, through the QWEN_MANIFEST hook, for the fetch script;
  * a fake `llama-server` whose --help text is under the test's control, for the serve script.

Every "must refuse" case here is a deliberately broken input that has to produce a
failure -- a check that cannot fail is not a check (CLAUDE.md).

    python3 -I scripts/test_qwen_local.py
"""
import hashlib
import os
import re
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent
FETCH = SCRIPTS / "qwen-local-fetch.sh"
SERVE = SCRIPTS / "qwen-local-serve.sh"


def run(cmd, env=None, cwd=None):
    e = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp")}
    e.update(env or {})
    p = subprocess.run(["bash", *map(str, cmd)], env=e, cwd=cwd, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


def make_exe(path: Path, body: str):
    path.write_text("#!/usr/bin/env bash\n" + textwrap.dedent(body))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def gguf(payload: bytes = b"x" * 40) -> bytes:
    return b"GGUF" + payload


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.dir = self.tmp / "models"
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.log = self.tmp / "curl.log"
        self.blob = gguf()
        self.sha = hashlib.sha256(self.blob).hexdigest()
        self.manifest = self.tmp / "manifest"
        self.manifest.write_text(f"a.gguf|{len(self.blob)}|{self.sha}\n")
        # fake curl: records its arguments and writes the blob to the -o target
        make_exe(self.bin / "curl", f"""
            echo "$@" >> "{self.log}"
            out=""
            while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
            printf '%s' "$FAKE_BODY" > "$out"
        """)

    def env(self, **kw):
        e = {"PATH": f"{self.bin}:{os.environ['PATH']}", "QWEN_DIR": str(self.dir),
             "QWEN_MANIFEST": str(self.manifest), "FAKE_BODY": self.blob.decode("latin-1")}
        e.update(kw)
        return e

    def test_downloads_a_missing_file_from_the_pinned_revision_with_resume(self):
        code, out, err = run([FETCH], self.env())
        self.assertEqual(code, 0, out + err)
        call = self.log.read_text()
        self.assertIn("a316ea527fde32c12487be7574e2db5ac2ad2a7e/a.gguf", call, "must use the pinned commit, not `main`")
        self.assertIn("-C -", call, "downloads must resume")
        self.assertNotIn("/main/", call)
        self.assertIn("sha256 verified", out)

    def test_check_never_downloads(self):
        code, out, err = run([FETCH, "--check"], self.env())
        self.assertEqual(code, 1, "a missing file under --check must fail")
        self.assertFalse(self.log.exists(), "--check must not call curl")

    def test_a_present_correct_file_is_not_downloaded_again(self):
        self.dir.mkdir()
        (self.dir / "a.gguf").write_bytes(self.blob)
        code, out, err = run([FETCH], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertFalse(self.log.exists(), "a verified file must not be fetched again")

    def test_wrong_hash_same_size_fails(self):
        self.dir.mkdir()
        (self.dir / "a.gguf").write_bytes(gguf(b"y" * 40))   # same length, different bytes
        code, out, err = run([FETCH, "--check"], self.env())
        self.assertEqual(code, 1)
        self.assertIn("sha256", err)

    def test_wrong_size_fails(self):
        self.dir.mkdir()
        (self.dir / "a.gguf").write_bytes(self.blob[:-5])
        code, out, err = run([FETCH, "--check"], self.env())
        self.assertEqual(code, 1)
        # the cheap size check must fail first: hashing a truncated 28 GB file is wasted time
        self.assertIn("bytes, expected", err)
        self.assertNotIn("sha256", err)

    def test_not_a_gguf_fails_even_with_matching_size_and_hash(self):
        blob = b"NOPE" + b"x" * 40
        self.manifest.write_text(f"a.gguf|{len(blob)}|{hashlib.sha256(blob).hexdigest()}\n")
        self.dir.mkdir()
        (self.dir / "a.gguf").write_bytes(blob)
        code, out, err = run([FETCH, "--check"], self.env())
        self.assertEqual(code, 1)
        self.assertIn("GGUF magic", err)

    def test_an_oversized_file_is_not_resumed_onto(self):
        self.dir.mkdir()
        (self.dir / "a.gguf").write_bytes(self.blob + b"junk")
        code, out, err = run([FETCH], self.env())
        self.assertEqual(code, 1)
        self.assertFalse(self.log.exists(), "must not curl -C - onto a file larger than expected")

    def test_a_truncated_download_that_curl_reports_as_fine_is_still_caught(self):
        self.env_body = self.blob[:-3].decode("latin-1")
        code, out, err = run([FETCH], self.env(FAKE_BODY=self.env_body))
        self.assertEqual(code, 1, out + err)

    def test_the_real_manifest_names_all_four_files_with_64_hex_hashes(self):
        text = FETCH.read_text()
        rows = re.findall(r'"([^"|]+\.gguf)\|(\d+)\|([0-9a-f]{64})"', text)
        names = {r[0] for r in rows}
        self.assertEqual(names, {"Qwen3.8-27B-Q8_0.gguf", "mmproj-Qwen3.8-27B-Q8_0.gguf",
                                 "mtp-Qwen3.8-27B-Q8_0.gguf", "dflash-Qwen3.8-27B-Q8_0.gguf"})
        self.assertTrue(re.search(r'^REV="[0-9a-f]{40}"', text, re.M), "REV must be a full commit sha")


class ServeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.dir = self.tmp / "models"
        self.dir.mkdir()
        for n in ("Qwen3.8-27B-Q8_0", "mmproj-Qwen3.8-27B-Q8_0", "mtp-Qwen3.8-27B-Q8_0", "dflash-Qwen3.8-27B-Q8_0"):
            (self.dir / f"{n}.gguf").write_bytes(gguf())
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.rec = self.tmp / "server.args"

    def fake_server(self, help_text: str):
        make_exe(self.bin / "llama-server", f"""
            if [ "$1" = "--help" ]; then cat <<'EOF'
{help_text}
EOF
              exit 0; fi
            echo "$@" > "{self.rec}"
        """)

    def env(self, **kw):
        e = {"QWEN_DIR": str(self.dir), "LLAMA_SERVER": str(self.bin / "llama-server")}
        e.update(kw)
        return e

    FULL_HELP = "--mmproj FILE\n--alias NAME\n--jinja\n--spec-type [none|draft-mtp|draft-dflash]\n"

    def test_mtp_command(self):
        code, out, err = run([SERVE, "--dry-run"], self.env())
        self.assertEqual(code, 0, out + err)
        for want in ("--mmproj " + str(self.dir / "mmproj-Qwen3.8-27B-Q8_0.gguf"), "--alias qwen3.8-27b-q8",
                     "-c 262144", "-np 1", "--jinja", "--host 127.0.0.1", "--port 8080",
                     "--spec-type draft-mtp", "--model-draft " + str(self.dir / "mtp-Qwen3.8-27B-Q8_0.gguf"),
                     "--spec-draft-n-max 3"):
            self.assertIn(want, out)
        self.assertNotIn("dflash", out.split("serving")[1])

    def test_dflash_command_uses_the_drafter_and_its_block_size(self):
        code, out, err = run([SERVE, "--dry-run", "--spec", "dflash"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertIn("--spec-type draft-dflash", out)
        self.assertIn("dflash-Qwen3.8-27B-Q8_0.gguf", out)
        self.assertIn("--spec-draft-n-max 8", out)
        self.assertNotIn("draft-mtp", out)

    def test_spec_none_has_no_speculation_flags(self):
        code, out, err = run([SERVE, "--dry-run", "--spec", "none"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertNotIn("--spec-type", out)
        self.assertNotIn("--model-draft", out)

    def test_unknown_spec_is_refused(self):
        code, out, err = run([SERVE, "--dry-run", "--spec", "both"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("mtp, dflash or none", err)

    def test_a_non_loopback_host_is_refused(self):
        for host in ("0.0.0.0", "192.168.1.5", "spark.local"):
            code, out, err = run([SERVE, "--dry-run"], self.env(QWEN_HOST=host))
            self.assertEqual(code, 2, host)
            self.assertIn("loopback", err)

    def test_missing_head_is_named_and_points_at_the_fetch_script(self):
        (self.dir / "mtp-Qwen3.8-27B-Q8_0.gguf").unlink()
        code, out, err = run([SERVE, "--dry-run"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("mtp-Qwen3.8-27B-Q8_0.gguf", err)
        self.assertIn("qwen-local-fetch.sh", err)

    def test_a_missing_head_does_not_block_a_mode_that_does_not_use_it(self):
        (self.dir / "mtp-Qwen3.8-27B-Q8_0.gguf").unlink()
        code, out, err = run([SERVE, "--dry-run", "--spec", "dflash"], self.env())
        self.assertEqual(code, 0, out + err)

    def test_missing_vision_projector_is_refused_in_every_mode(self):
        (self.dir / "mmproj-Qwen3.8-27B-Q8_0.gguf").unlink()
        for spec in ("mtp", "dflash", "none"):
            code, out, err = run([SERVE, "--dry-run", "--spec", spec], self.env())
            self.assertEqual(code, 2, spec)

    def test_preflight_refuses_a_build_without_mtp(self):
        self.fake_server("--mmproj FILE\n--alias NAME\n--jinja\n--spec-type [none|draft-dflash]\n")
        code, out, err = run([SERVE], self.env())
        self.assertEqual(code, 2, out + err)
        self.assertIn("draft-mtp", err)
        self.assertFalse(self.rec.exists(), "the server must not start on a build that lacks the flag")

    def test_preflight_refuses_a_build_without_spec_type_at_all(self):
        self.fake_server("--mmproj FILE\n--alias NAME\n--jinja\n")
        code, out, err = run([SERVE, "--spec", "dflash"], self.env())
        self.assertEqual(code, 2, out + err)

    def test_preflight_passes_and_execs_the_server_with_the_flags(self):
        self.fake_server(self.FULL_HELP)
        code, out, err = run([SERVE], self.env())
        self.assertEqual(code, 0, out + err)
        args = self.rec.read_text()
        self.assertIn("--spec-type draft-mtp", args)
        self.assertIn("--alias qwen3.8-27b-q8", args)

    def test_spec_none_needs_no_spec_flags_in_the_build(self):
        self.fake_server("--mmproj FILE\n--alias NAME\n--jinja\n")
        code, out, err = run([SERVE, "--spec", "none"], self.env())
        self.assertEqual(code, 0, out + err)

    def test_no_preflight_overrides_the_check(self):
        self.fake_server("--mmproj FILE\n--alias NAME\n--jinja\n")
        code, out, err = run([SERVE, "--no-preflight"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertTrue(self.rec.exists())

    def test_a_missing_binary_is_reported(self):
        code, out, err = run([SERVE], self.env(LLAMA_SERVER=str(self.bin / "nope")))
        self.assertEqual(code, 2)
        self.assertIn("not found", err)


class ConfigAgreesWithScripts(unittest.TestCase):
    """The scripts and configs/hermes/config.yaml each name the alias and the window."""

    def test_alias_and_context_match_the_config(self):
        import yaml
        cfg = yaml.safe_load((REPO / "configs/hermes/config.yaml").read_text(encoding="utf-8"))
        prov = cfg["providers"]["llamacpp-qwen"]
        serve = SERVE.read_text()
        alias = re.search(r'^ALIAS="\$\{QWEN_ALIAS:-([^}]+)\}"', serve, re.M).group(1)
        ctx = int(re.search(r'^CTX="\$\{QWEN_CTX:-(\d+)\}"', serve, re.M).group(1))
        port = int(re.search(r'^PORT="\$\{QWEN_PORT:-(\d+)\}"', serve, re.M).group(1))
        self.assertEqual(alias, prov["default_model"])
        self.assertEqual([alias], prov["models"])
        self.assertEqual(ctx, prov["context_length"])
        self.assertTrue(prov["api"].startswith("http://127.0.0.1:"), "must stay loopback (tunnel)")
        fb = [f for f in cfg["fallback_providers"] if f.get("base_url") == prov["api"]]
        self.assertEqual(len(fb), 1, "exactly one fallback link uses the tunnel")
        self.assertEqual(fb[0]["model"], alias)
        # the tunnel's REMOTE end is the port the server binds; documented in the config
        self.assertIn(f"127.0.0.1:{port}", (REPO / "configs/hermes/config.yaml").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
