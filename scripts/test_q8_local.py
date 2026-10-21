"""Tests for scripts/q8-local-fetch.sh and scripts/q8-local-serve.sh.

Neither script can be run for real in CI: the fetch pulls up to 594 GB, the serve needs a
CUDA build of llama.cpp and a box with 130 GB to 1 TB of memory. So the tests run them as a
user would, against stand-ins:

  * a fake `curl` and tiny files, through the Q8_MANIFEST hook, for the fetch script;
  * a fake `llama-server` whose --help text is under the test's control, for the serve script.

Every "must refuse" case here is a deliberately broken input that has to produce a
failure -- a check that cannot fail is not a check (CLAUDE.md).

    python3 -I scripts/test_q8_local.py
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
FETCH = SCRIPTS / "q8-local-fetch.sh"
SERVE = SCRIPTS / "q8-local-serve.sh"

MODELS = ("supervl", "ultra", "glm")
PROVIDER = {"supervl": "llamacpp-supervl-q8", "ultra": "llamacpp-ultra-q8", "glm": "llamacpp-glm-q8"}
# sizes summed from the Hugging Face tree API, 2026-10-21
TOTAL_BYTES = {"supervl": 133716911008, "ultra": 594513314336, "glm": 342110013504}
FILE_COUNT = {"supervl": 3, "ultra": 14, "glm": 9}


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


def real_manifest(key):
    """The (remote, bytes, sha256) rows the fetch script really ships for one model."""
    text = FETCH.read_text()
    block = re.search(rf"^FILES_{key}=\(\n(.*?)\n\)", text, re.S | re.M).group(1)
    return re.findall(r'"([^"|]+)\|(\d+)\|([0-9a-f]{64})"', block)


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.base = self.tmp / "models"
        self.dir = self.base / "ultra"          # the model under test
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.log = self.tmp / "curl.log"
        self.blob = gguf()
        self.sha = hashlib.sha256(self.blob).hexdigest()
        self.manifest = self.tmp / "manifest"
        self.manifest.write_text(f"sub/dir/a.gguf|{len(self.blob)}|{self.sha}\n")
        # fake curl: records its arguments and writes the blob to the -o target
        make_exe(self.bin / "curl", f"""
            echo "$@" >> "{self.log}"
            out=""
            while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
            printf '%s' "$FAKE_BODY" > "$out"
        """)

    def env(self, **kw):
        e = {"PATH": f"{self.bin}:{os.environ['PATH']}", "Q8_DIR": str(self.base),
             "Q8_MANIFEST": str(self.manifest), "FAKE_BODY": self.blob.decode("latin-1")}
        e.update(kw)
        return e

    def test_downloads_a_missing_file_from_the_pinned_revision_of_its_own_repo(self):
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 0, out + err)
        call = self.log.read_text()
        text = FETCH.read_text()
        rev = re.search(r'^REV_ultra="([0-9a-f]{40})"', text, re.M).group(1)
        repo = re.search(r'^REPO_ultra="([^"]+)"', text, re.M).group(1)
        self.assertIn(f"https://huggingface.co/{repo}/resolve/{rev}/sub/dir/a.gguf", call,
                      "must use the pinned commit and the remote path, not `main`")
        self.assertIn("-C -", call, "downloads must resume")
        self.assertNotIn("/main/", call)
        self.assertIn("sha256 verified", out)

    def test_the_local_file_is_the_basename_in_a_per_model_directory(self):
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertTrue((self.dir / "a.gguf").is_file(), "llama-server finds shards by the name of shard 1, so no subdirectory")
        self.assertFalse((self.dir / "sub").exists())

    def test_each_model_uses_its_own_repo_and_directory(self):
        code, out, err = run([FETCH, "supervl", "glm"], self.env())
        self.assertEqual(code, 0, out + err)
        text = FETCH.read_text()
        calls = self.log.read_text()
        for key in ("supervl", "glm"):
            repo = re.search(rf'^REPO_{key}="([^"]+)"', text, re.M).group(1)
            self.assertIn(f"huggingface.co/{repo}/", calls)
            self.assertTrue((self.base / key / "a.gguf").is_file())
        self.assertNotIn("Ultra", calls)

    def test_all_means_the_three_models(self):
        code, out, err = run([FETCH, "all"], self.env())
        self.assertEqual(code, 0, out + err)
        for key in MODELS:
            self.assertTrue((self.base / key / "a.gguf").is_file(), key)

    def test_check_never_downloads(self):
        code, out, err = run([FETCH, "ultra", "--check"], self.env())
        self.assertEqual(code, 1, "a missing file under --check must fail")
        self.assertFalse(self.log.exists(), "--check must not call curl")

    def test_a_present_correct_file_is_not_downloaded_again(self):
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(self.blob)
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertFalse(self.log.exists(), "a verified file must not be fetched again")

    def test_wrong_hash_same_size_fails(self):
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(gguf(b"y" * 40))   # same length, different bytes
        code, out, err = run([FETCH, "ultra", "--check"], self.env())
        self.assertEqual(code, 1)
        self.assertIn("sha256", err)

    def test_wrong_size_fails_before_hashing(self):
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(self.blob[:-5])
        code, out, err = run([FETCH, "ultra", "--check"], self.env())
        self.assertEqual(code, 1)
        # hashing a truncated 48 GB shard is wasted time: the cheap size check must fail first
        self.assertIn("bytes, expected", err)
        self.assertNotIn("sha256", err)

    def test_not_a_gguf_fails_even_with_matching_size_and_hash(self):
        blob = b"NOPE" + b"x" * 40
        self.manifest.write_text(f"a.gguf|{len(blob)}|{hashlib.sha256(blob).hexdigest()}\n")
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(blob)
        code, out, err = run([FETCH, "ultra", "--check"], self.env())
        self.assertEqual(code, 1)
        self.assertIn("GGUF magic", err)

    def test_an_oversized_file_is_not_resumed_onto(self):
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(self.blob + b"junk")
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 1)
        self.assertFalse(self.log.exists(), "must not curl -C - onto a file larger than expected")

    def test_a_truncated_download_that_curl_reports_as_fine_is_still_caught(self):
        code, out, err = run([FETCH, "ultra"], self.env(FAKE_BODY=self.blob[:-3].decode("latin-1")))
        self.assertEqual(code, 1, out + err)

    def test_one_bad_file_fails_the_run_even_when_others_verify(self):
        good = gguf(b"g" * 10)
        self.manifest.write_text(
            f"good.gguf|{len(good)}|{hashlib.sha256(good).hexdigest()}\n"
            f"bad.gguf|{len(self.blob)}|{'0' * 64}\n")
        self.dir.mkdir(parents=True)
        (self.dir / "good.gguf").write_bytes(good)
        (self.dir / "bad.gguf").write_bytes(self.blob)
        code, out, err = run([FETCH, "ultra", "--check"], self.env())
        self.assertEqual(code, 1)
        self.assertIn("ok    ultra/good.gguf", out)
        self.assertIn("FAILED", err)

    def test_not_enough_disk_is_refused_before_any_download(self):
        self.manifest.write_text(f"huge.gguf|{10**18}|{self.sha}\n")
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 1, out + err)
        self.assertIn("free", err)
        self.assertFalse(self.log.exists(), "must not start a download that cannot fit")

    def test_the_disk_check_can_be_overridden(self):
        self.manifest.write_text(f"huge.gguf|{10**18}|{self.sha}\n")
        code, out, err = run([FETCH, "ultra"], self.env(Q8_SKIP_DISK_CHECK="1"))
        self.assertTrue(self.log.exists(), "with the override the download is attempted")
        self.assertEqual(code, 1, "and the tiny fake body then fails the size check")

    def test_disk_check_counts_only_what_is_still_missing(self):
        # a 10**18-byte file is "already here" up to its full size: nothing remains to fit
        self.dir.mkdir(parents=True)
        (self.dir / "a.gguf").write_bytes(self.blob)
        code, out, err = run([FETCH, "ultra"], self.env())
        self.assertEqual(code, 0, out + err)

    def test_no_model_and_unknown_model_are_refused(self):
        code, out, err = run([FETCH], self.env())
        self.assertEqual(code, 2)
        code, out, err = run([FETCH, "qwen"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("unknown argument", err)

    # ---- the shipped manifests ----
    def test_the_real_manifests_are_complete_and_well_formed(self):
        text = FETCH.read_text()
        for key in MODELS:
            self.assertTrue(re.search(rf'^REV_{key}="[0-9a-f]{{40}}"', text, re.M), f"{key}: REV must be a full commit sha")
            rows = real_manifest(key)
            self.assertEqual(len(rows), FILE_COUNT[key], key)
            self.assertEqual(sum(int(r[1]) for r in rows), TOTAL_BYTES[key], f"{key}: total bytes")
            self.assertEqual(len({r[2] for r in rows}), len(rows), f"{key}: duplicate hashes would mean a copy-paste error")
            for remote, size, sha in rows:
                self.assertTrue(remote.endswith(".gguf"), remote)
                self.assertGreater(int(size), 0)

    def test_ultra_is_all_fourteen_q8_k_xl_shards_in_order(self):
        names = [r[0].rsplit("/", 1)[-1] for r in real_manifest("ultra")]
        want = [f"NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-{i:05d}-of-00014.gguf" for i in range(1, 15)]
        self.assertEqual(names, want)

    def test_glm_is_eight_q8_0_shards_and_the_f16_projector(self):
        names = [r[0].rsplit("/", 1)[-1] for r in real_manifest("glm")]
        want = [f"GLM-5.3-Flash-Q8_0-{i:05d}-of-00008.gguf" for i in range(1, 9)] + ["mmproj-F16.gguf"]
        self.assertEqual(names, want)

    def test_supervl_is_the_model_its_projector_and_its_mtp_head(self):
        names = sorted(r[0] for r in real_manifest("supervl"))
        self.assertEqual(names, sorted([
            "NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf",
            "mmproj-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf",
            "mtp-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"]))


class ServeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.base = self.tmp / "models"
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.rec = self.tmp / "server.args"
        # lay each model's files out exactly as the fetch script's manifest names them
        for key in MODELS:
            d = self.base / key
            d.mkdir(parents=True)
            for remote, _, _ in real_manifest(key):
                (d / remote.rsplit("/", 1)[-1]).write_bytes(gguf())

    def d(self, key):
        return self.base / key

    def fake_server(self, help_text: str):
        make_exe(self.bin / "llama-server", f"""
            if [ "$1" = "--help" ]; then cat <<'EOF'
{help_text}
EOF
              exit 0; fi
            echo "$@" > "{self.rec}"
        """)

    def env(self, **kw):
        e = {"Q8_DIR": str(self.base), "LLAMA_SERVER": str(self.bin / "llama-server")}
        e.update(kw)
        return e

    FULL_HELP = "--mmproj FILE\n--alias NAME\n--jinja\n--spec-type [none|draft-mtp]\n"

    def test_the_files_the_fetch_script_ships_are_exactly_enough_to_serve_every_model(self):
        # ties the two scripts together: a renamed file in one and not the other fails here
        for key in MODELS:
            code, out, err = run([SERVE, key, "--dry-run"], self.env())
            self.assertEqual(code, 0, f"{key}: {out}{err}")

    def test_supervl_command(self):
        code, out, err = run([SERVE, "supervl", "--dry-run"], self.env())
        self.assertEqual(code, 0, out + err)
        d = self.d("supervl")
        for want in ("-m " + str(d / "NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"),
                     "--mmproj " + str(d / "mmproj-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"),
                     "--alias nemotron-3.5-super-vl-120b-a12b-q8", "-c 131072", "-np 1", "--jinja",
                     "--temp 1.0", "--top-p 0.95", "--host 127.0.0.1", "--port 8082"):
            self.assertIn(want, out)
        self.assertNotIn("--spec-type", out, "speculation is opt-in")

    def test_ultra_command_is_text_only_and_opens_shard_one(self):
        code, out, err = run([SERVE, "ultra", "--dry-run"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertIn("NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00001-of-00014.gguf", out)
        self.assertIn("--alias nemotron-3-ultra-550b-a55b-q8", out)
        self.assertIn("--port 8083", out)
        self.assertNotIn("--mmproj", out)
        self.assertNotIn("--spec-type", out)

    def test_glm_command_has_its_projector_and_its_own_port(self):
        code, out, err = run([SERVE, "glm", "--dry-run"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertIn("--mmproj " + str(self.d("glm") / "mmproj-F16.gguf"), out)
        self.assertIn("GLM-5.3-Flash-Q8_0-00001-of-00008.gguf", out)
        self.assertIn("--alias glm-5.3-flash-q8", out)
        self.assertIn("--port 8084", out)

    def test_the_three_servers_never_share_a_port_or_an_alias(self):
        seen = {}
        for key in MODELS:
            code, out, err = run([SERVE, key, "--print"], self.env())
            self.assertEqual(code, 0, out + err)
            kv = dict(l.split("=", 1) for l in out.splitlines())
            seen[key] = kv
        self.assertEqual(len({v["PORT"] for v in seen.values()}), 3)
        self.assertEqual(len({v["ALIAS"] for v in seen.values()}), 3)
        self.assertNotIn("8080", {v["PORT"] for v in seen.values()}, "8080 is the Qwen server's remote port")
        self.assertNotIn("8081", {v["PORT"] for v in seen.values()})

    def test_supervl_mtp_adds_the_head_and_its_draft_length(self):
        code, out, err = run([SERVE, "supervl", "--dry-run", "--spec", "mtp"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertIn("--spec-type draft-mtp", out)
        self.assertIn("--model-draft " + str(self.d("supervl") / "mtp-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf"), out)
        self.assertIn("--spec-draft-n-max 3", out)

    def test_mtp_is_refused_for_the_models_that_have_none_wired(self):
        for key in ("ultra", "glm"):
            code, out, err = run([SERVE, key, "--dry-run", "--spec", "mtp"], self.env())
            self.assertEqual(code, 2, key)
            self.assertIn("only wired for supervl", err)

    def test_unknown_spec_is_refused(self):
        code, out, err = run([SERVE, "supervl", "--dry-run", "--spec", "dflash"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("mtp or none", err)

    def test_a_non_loopback_host_is_refused_for_every_model(self):
        for key in MODELS:
            for host in ("0.0.0.0", "192.168.1.5", "spark.local"):
                code, out, err = run([SERVE, key, "--dry-run"], self.env(Q8_HOST=host))
                self.assertEqual(code, 2, f"{key} {host}")
                self.assertIn("loopback", err)

    def test_a_missing_later_shard_is_named_and_points_at_the_fetch_script(self):
        (self.d("ultra") / "NVIDIA-Nemotron-3-Ultra-550B-A55B-UD-Q8_K_XL-00007-of-00014.gguf").unlink()
        code, out, err = run([SERVE, "ultra", "--dry-run"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("00007-of-00014", err)
        self.assertIn("q8-local-fetch.sh ultra", err)

    def test_a_missing_last_shard_is_caught_too(self):
        (self.d("glm") / "GLM-5.3-Flash-Q8_0-00008-of-00008.gguf").unlink()
        code, out, err = run([SERVE, "glm", "--dry-run"], self.env())
        self.assertEqual(code, 2)
        self.assertIn("00008-of-00008", err)

    def test_a_missing_projector_is_refused_where_one_is_used(self):
        (self.d("supervl") / "mmproj-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf").unlink()
        code, out, err = run([SERVE, "supervl", "--dry-run"], self.env())
        self.assertEqual(code, 2)
        (self.d("glm") / "mmproj-F16.gguf").unlink()
        code, out, err = run([SERVE, "glm", "--dry-run"], self.env())
        self.assertEqual(code, 2)

    def test_a_missing_mtp_head_only_matters_when_asked_for(self):
        (self.d("supervl") / "mtp-NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-Q8_0.gguf").unlink()
        code, out, err = run([SERVE, "supervl", "--dry-run"], self.env())
        self.assertEqual(code, 0, out + err)
        code, out, err = run([SERVE, "supervl", "--dry-run", "--spec", "mtp"], self.env())
        self.assertEqual(code, 2)

    def test_extra_arguments_after_double_dash_reach_the_server(self):
        code, out, err = run([SERVE, "glm", "--dry-run", "--", "-ts", "1,1,1,1", "--no-warmup"], self.env())
        self.assertEqual(code, 0, out + err)
        # the dry run prints a shell-quoted command (printf %q escapes the commas)
        self.assertIn("-ts 1\\,1\\,1\\,1", out)
        self.assertIn("--no-warmup", out)

    def test_no_model_and_unknown_model_are_refused(self):
        code, out, err = run([SERVE], self.env())
        self.assertEqual(code, 2)
        code, out, err = run([SERVE, "qwen"], self.env())
        self.assertEqual(code, 2)

    def test_preflight_demands_the_projector_flag_only_where_one_is_used(self):
        self.fake_server("--alias NAME\n--jinja\n")
        code, out, err = run([SERVE, "supervl"], self.env())
        self.assertEqual(code, 2, out + err)
        self.assertIn("--mmproj", err)
        self.assertFalse(self.rec.exists(), "the server must not start on a build that lacks the flag")
        code, out, err = run([SERVE, "ultra"], self.env())
        self.assertEqual(code, 0, "ultra uses no projector, so a build without --mmproj is fine: " + out + err)

    def test_preflight_refuses_a_build_without_mtp_when_mtp_is_asked_for(self):
        self.fake_server("--mmproj FILE\n--alias NAME\n--jinja\n")
        code, out, err = run([SERVE, "supervl", "--spec", "mtp"], self.env())
        self.assertEqual(code, 2, out + err)
        self.assertIn("draft-mtp", err)

    def test_preflight_passes_and_execs_the_server_with_the_flags(self):
        self.fake_server(self.FULL_HELP)
        code, out, err = run([SERVE, "supervl", "--spec", "mtp"], self.env())
        self.assertEqual(code, 0, out + err)
        args = self.rec.read_text()
        self.assertIn("--spec-type draft-mtp", args)
        self.assertIn("--alias nemotron-3.5-super-vl-120b-a12b-q8", args)

    def test_glm_says_out_loud_that_it_needs_a_special_build(self):
        self.fake_server(self.FULL_HELP)
        code, out, err = run([SERVE, "glm"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertIn("glm5next", err)

    def test_no_preflight_overrides_the_check(self):
        self.fake_server("--jinja\n")
        code, out, err = run([SERVE, "supervl", "--no-preflight"], self.env())
        self.assertEqual(code, 0, out + err)
        self.assertTrue(self.rec.exists())

    def test_a_missing_binary_is_reported(self):
        code, out, err = run([SERVE, "ultra"], self.env(LLAMA_SERVER=str(self.bin / "nope")))
        self.assertEqual(code, 2)
        self.assertIn("not found", err)


class ConfigAgreesWithScripts(unittest.TestCase):
    """The serve script and configs/hermes/config.yaml each name the alias, window and port."""

    @classmethod
    def setUpClass(cls):
        import yaml
        cls.cfg = yaml.safe_load((REPO / "configs/hermes/config.yaml").read_text(encoding="utf-8"))
        cls.cfg_text = (REPO / "configs/hermes/config.yaml").read_text(encoding="utf-8")

    def printed(self, key):
        code, out, err = run([SERVE, key, "--print"])
        self.assertEqual(code, 0, out + err)
        return dict(l.split("=", 1) for l in out.splitlines())

    def test_alias_context_and_port_match_each_provider(self):
        for key in MODELS:
            kv = self.printed(key)
            prov = self.cfg["providers"][PROVIDER[key]]
            self.assertEqual(kv["ALIAS"], prov["default_model"], key)
            self.assertEqual([kv["ALIAS"]], prov["models"], key)
            self.assertEqual(int(kv["CTX"]), prov["context_length"], key)
            self.assertEqual(prov["api"], f"http://127.0.0.1:{kv['PORT']}/v1", f"{key}: must be loopback on the script's port")
            self.assertNotIn("key_env", prov, key)
            self.assertIs(prov["discover_models"], False, key)

    def test_the_supervl_alias_keeps_the_parents_compaction_threshold(self):
        # the threshold key is matched by substring against the model id Hermes is using
        alias = self.printed("supervl")["ALIAS"]
        keys = [k for k in self.cfg["compression"]["model_thresholds"] if k.lower() in alias.lower()]
        self.assertTrue(keys, f"no compression.model_thresholds key matches {alias}")

    def test_supervl_is_exactly_one_fallback_link_and_the_others_are_none(self):
        chain = self.cfg["fallback_providers"]
        for key in MODELS:
            prov = self.cfg["providers"][PROVIDER[key]]
            hits = [f for f in chain if f.get("base_url") == prov["api"]]
            if key == "supervl":
                self.assertEqual(len(hits), 1)
                self.assertEqual(hits[0]["model"], prov["default_model"])
            else:
                self.assertEqual(hits, [], f"{key} is an opt-in MoA reference, not a fallback")

    def test_supervl_sits_after_openrouter_and_huggingface(self):
        hosts = [f["base_url"] for f in self.cfg["fallback_providers"]]
        self.assertEqual(hosts[0], "https://openrouter.ai/api/v1")
        self.assertEqual(hosts[1], "https://router.huggingface.co/v1")
        self.assertEqual(hosts[2], "http://127.0.0.1:8082/v1")

    def test_the_default_preset_keeps_the_hosted_references(self):
        moa = self.cfg["moa"]
        default = moa["presets"][moa["default_preset"]]
        for r in default["reference_models"] + moa["reference_models"]:
            self.assertNotIn("llamacpp", r["provider"], "the default roster stays hosted; the local copies are opt-in")

    def test_the_local_preset_uses_the_local_ultra_and_glm(self):
        pre = self.cfg["moa"]["presets"]["local-q8"]
        pairs = {(r["provider"], r["model"]) for r in pre["reference_models"]}
        for key in ("ultra", "glm"):
            alias = self.printed(key)["ALIAS"]
            self.assertIn((f"custom:{PROVIDER[key]}", alias), pairs)
        self.assertNotIn("supervl", " ".join(p for p, _ in pairs), "Super VL is the aggregator, never its own adviser")

    def test_every_aggregator_stays_the_hosted_full_size_super_vl(self):
        want = {"provider": "custom:nvidia-nim", "model": "nvidia/nemotron-3.5-super-vl-120b-a12b"}
        moa = self.cfg["moa"]
        self.assertEqual({k: moa["aggregator"][k] for k in want}, want)
        for name, pre in moa["presets"].items():
            self.assertEqual({k: pre["aggregator"][k] for k in want}, want, f"preset {name}")

    def test_each_tunnels_remote_port_is_documented_in_the_config(self):
        for key in MODELS:
            port = self.printed(key)["PORT"]
            self.assertIn(f"ssh -N -L {port}:127.0.0.1:{port}", self.cfg_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
