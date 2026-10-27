"""Standard-library orchestration checks using a fake bcftools executable."""

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="idat2vcf-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root / "data"
        self.inputs = self.data / "idat_files"
        self.inputs.mkdir(parents=True)
        for channel in ("Grn", "Red"):
            (self.inputs / f"sample_{channel}.idat").write_text("test input\n")
        self.logs = self.root / "logs"
        resources = self.root / "resources"
        resources.mkdir()
        for line in (ROOT / "resources.sha256").read_text().splitlines():
            (resources / line.split()[1]).write_text("test resource\n")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        tool = bin_dir / "bcftools"
        shutil.copyfile(ROOT / "tests/fixtures/bcftools", tool)
        tool.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "DATA_DIR": str(self.data),
            "LOG_DIR": str(self.logs),
            "IDAT2VCF_RESOURCES_DIR": str(resources),
            "MOCK_FAIL": "",
            "MOCK_LOG_FAILURE_FLAG": "",
            "MOCK_STAGE_SLEEP": "",
            "HOST_LOG_DIR": "",
            "EXPECTED_VCF_RECORDS": "1",
            "LOG_LEVEL": "PROCESS",
            "LOGSHURU_OUTPUT": "stderr",
            "LOGSHURU_FORMAT": "text",
            "LOGSHURU_COLOR": "never",
            "LOGSHURU_TZ": "UTC",
        }
        self.host_tee = shutil.which("tee")
        self.host_date = shutil.which("date")

    def run_pipeline(self, *args):
        return subprocess.run(
            ["bash", str(ROOT / "idat2vcf.docker.sh"), *args],
            env=self.env, capture_output=True, text=True, timeout=15,
        )

    def assert_unlocked(self):
        self.assertFalse((self.data / ".PROJECT.idat2vcf.lock").exists())

    def test_success_and_repeated_run_protection(self):
        unrelated = self.data / "gtc_files"
        unrelated.mkdir()
        sentinel = unrelated / "existing.gtc"
        sentinel.write_text("keep")
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        self.assertTrue(result.stdout.startswith(f"SUCCESS: PROJECT completed. Log: {self.logs}/"))
        self.assertEqual(result.stderr, "")
        self.assertNotIn("bcftools test double", result.stdout)
        for suffix in ("vcf.gz", "vcf.gz.csi", "extra.tsv"):
            self.assertTrue((self.data / f"PROJECT.{suffix}").is_file())
        self.assertEqual(sentinel.read_text(), "keep")
        self.assertEqual(list(self.data.glob(".PROJECT.idat2vcf.*")), [])
        self.assertEqual(len(list(self.logs.glob("*.log"))), 1)
        log_text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("| PROCESS", log_text)
        self.assertIn("| SUCCESS", log_text)
        self.assertRegex(log_text, r"idat2vcf\.docker\.sh:cleanup:\d+ - Completed project")
        self.assertEqual(log_text.count("Completed project: PROJECT"), 1)
        self.assertNotIn("\x1b[", log_text)
        self.assertIn("Using bcftools 1.0-test", log_text)
        self.assertNotIn("Copyright (C)", log_text)
        self.assertNotIn("NO WARRANTY", log_text)
        self.assertNotRegex(log_text, r"(?m)^1$")
        previous = (self.data / "PROJECT.vcf.gz").read_bytes()
        repeated = self.run_pipeline("PROJECT")
        self.assertNotEqual(repeated.returncode, 0)
        self.assertTrue(repeated.stderr.startswith("FAILED: PROJECT (exit 1). Log: "))
        self.assertEqual(repeated.stdout, "")
        self.assertIn("Refusing to replace", "".join(p.read_text() for p in self.logs.glob("*.log")))
        self.assertEqual((self.data / "PROJECT.vcf.gz").read_bytes(), previous)
        self.assert_unlocked()

    def test_each_conversion_failure_is_logged_and_preserved(self):
        for stage in ("+idat2gtc", "+gtc2vcf", "sort", "norm"):
            with self.subTest(stage=stage):
                self.env["MOCK_FAIL"] = stage
                result = self.run_pipeline("PROJECT")
                self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(len(result.stderr.splitlines()), 1)
                self.assertIn("FAILED: PROJECT (exit 42). Log:", result.stderr)
                logs = "".join(p.read_text() for p in self.logs.glob("*.log"))
                self.assertIn(f"Injected failure: {stage}", logs)
                self.assertIn("Intermediates retained:", logs)
                self.assertFalse((self.data / "PROJECT.vcf.gz").exists())
                self.assert_unlocked()
        self.assertEqual(len(list(self.data.glob(".PROJECT.idat2vcf.*"))), 4)

    def test_verbose_flag_streams_and_drains_before_final_summary(self):
        for args in (("--verbose", "PROJECT_A"), ("PROJECT_B", "--verbose")):
            with self.subTest(args=args):
                result = self.run_pipeline(*args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertIn("| PROCESS", result.stdout)
                self.assertNotIn("| SUCCESS", result.stdout)
                self.assertNotIn("Completed project:", result.stdout)
                self.assertNotIn("Copyright (C)", result.stdout)
                self.assertNotRegex(result.stdout, r"(?m)^1$")
                self.assertTrue(result.stdout.splitlines()[-1].startswith("SUCCESS: "))
                self.assertEqual(list(self.data.glob(".*.idat2vcf.*")), [])

    def test_debug_details_and_no_console_banner(self):
        self.env["LOG_LEVEL"] = "DEBUG"
        result = self.run_pipeline("--verbose", "PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("Indexed records: 1", text)
        self.assertIn("Working directory:", text)
        self.assertIn("Using bcftools 1.0-test", text)
        self.assertIn("fake idat2gtc progress", text)
        self.assertNotIn("Copyright (C)", text)
        self.assertNotIn("Copyright (C)", result.stdout)
        self.assertNotRegex(result.stdout, r"(?m)^1$")
        self.assertTrue(result.stdout.splitlines()[-1].startswith("SUCCESS: "))

    def test_verbose_failure_keeps_tool_output_and_returns_original_status(self):
        self.env["MOCK_FAIL"] = "+idat2gtc"
        result = self.run_pipeline("--verbose", "PROJECT")
        self.assertEqual(result.returncode, 42)
        self.assertIn("Injected failure: +idat2gtc", result.stdout)
        self.assertIn("Intermediates retained:", result.stdout)
        self.assertIn("FAILED: PROJECT (exit 42). Log:", result.stderr)
        self.assertNotIn("SUCCESS: PROJECT", result.stdout)
        self.assert_unlocked()

    def test_cleanup_failure_cannot_report_success(self):
        rmdir = self.root / "bin/rmdir"
        rmdir.write_text("#!/usr/bin/env bash\nexit 74\n")
        rmdir.chmod(0o755)
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("FAILED: PROJECT", result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("Failed to release project lock", text)
        self.assertNotIn("| SUCCESS", text)
        self.assertTrue((self.data / ".PROJECT.idat2vcf.lock").exists())

    def test_host_log_dir_override_shows_system_path(self):
        for override in ("/host/system/logs/", "/host/system/my logs/"):
            with self.subTest(override=override):
                for suffix in ("vcf.gz", "vcf.gz.csi", "extra.tsv"):
                    path = self.data / f"PROJECT.{suffix}"
                    if path.exists():
                        path.unlink()
                self.env["HOST_LOG_DIR"] = override
                result = self.run_pipeline("PROJECT")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                expected_prefix = override.rstrip("/")
                self.assertRegex(
                    result.stdout,
                    r"(?m)^SUCCESS: PROJECT completed\. Log: " + re.escape(expected_prefix)
                    + r"/PROJECT_\S+\.log$",
                )
                text = max(self.logs.glob("*.log"), key=lambda p: p.stat().st_mtime).read_text()
                self.assertIn(f"log: {expected_prefix}/", text)
                self.assertNotIn("log: " + expected_prefix + "//", text)

    def test_invalid_host_log_dir_rejected_before_side_effects(self):
        self.env["HOST_LOG_DIR"] = "relative/logs"
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HOST_LOG_DIR must be an absolute path", result.stderr)
        self.assertFalse(self.logs.exists())

    def test_completion_event_reaches_log_for_all_logger_routing_modes(self):
        for mode in ("stderr", "stdout", "split"):
            with self.subTest(mode=mode):
                self.env["LOGSHURU_OUTPUT"] = mode
                result = self.run_pipeline("PROJECT")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                text = next(self.logs.glob("*.log")).read_text()
                self.assertEqual(text.count("Completed project: PROJECT"), 1)
                self.assertEqual(text.count("| SUCCESS"), 1)
                self.assertEqual(len(result.stdout.splitlines()), 1)
                self.assertTrue(result.stdout.startswith("SUCCESS: PROJECT completed."))
                for suffix in ("vcf.gz", "vcf.gz.csi", "extra.tsv"):
                    (self.data / f"PROJECT.{suffix}").unlink()

    def test_termination_prompts_cleanup_and_kills_pipeline(self):
        self.env["MOCK_STAGE_SLEEP"] = "8"
        process = subprocess.Popen(
            ["bash", str(ROOT / "idat2vcf.docker.sh"), "PROJECT"],
            env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        time.sleep(1.5)
        # Mirror docker stop semantics: SIGTERM reaches only the main process.
        # Time the kill from the signal, not from process start, so a slow
        # startup on a loaded machine cannot produce a false failure.
        sent = time.monotonic()
        process.terminate()
        out, err = process.communicate(timeout=30)
        elapsed = time.monotonic() - sent
        self.assertLess(elapsed, 6, "Termination did not interrupt the pipeline promptly")
        self.assertEqual(process.returncode, 143, out + err)
        self.assertTrue(err.startswith("FAILED: PROJECT (exit 143). Log: "), err)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("| WARNING", text)
        self.assertIn("Terminated", text)
        self.assertIn("Intermediates retained:", text)
        self.assert_unlocked()
        self.assertFalse((self.data / "PROJECT.vcf.gz").exists())
        self.assertEqual(len(list(self.data.glob(".PROJECT.idat2vcf.*"))), 1)

    def install_failing_tee(self):
        tee = self.root / "bin/tee"
        tee.write_text(f'#!/usr/bin/env bash\n{self.host_tee} "$@"\nexit 7\n')
        tee.chmod(0o755)

    def test_cleanup_failure_does_not_mask_tool_error(self):
        self.env["MOCK_FAIL"] = "+idat2gtc"
        rmdir = self.root / "bin/rmdir"
        rmdir.write_text("#!/usr/bin/env bash\nexit 74\n")
        rmdir.chmod(0o755)
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 42)
        self.assertIn("FAILED: PROJECT (exit 42). Log:", result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("Failed to release project lock", text)
        self.assertIn("Intermediates retained:", text)
        self.assertNotIn("| SUCCESS", text)

    def test_capture_failure_cannot_report_success(self):
        self.install_failing_tee()
        result = self.run_pipeline("--verbose", "PROJECT")
        self.assertEqual(result.returncode, 7)
        self.assertIn("FAILED: PROJECT (exit 7). Log:", result.stderr)
        self.assertNotIn("SUCCESS: PROJECT completed.", result.stdout)
        self.assert_unlocked()

    def test_capture_failure_does_not_mask_tool_error(self):
        self.install_failing_tee()
        self.env["MOCK_FAIL"] = "+idat2gtc"
        result = self.run_pipeline("--verbose", "PROJECT")
        self.assertEqual(result.returncode, 42)
        self.assertIn("FAILED: PROJECT (exit 42). Log:", result.stderr)
        self.assert_unlocked()

    def test_filtered_events_do_not_interrupt_conversion(self):
        self.env["LOG_LEVEL"] = "ERROR"
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertNotIn("| PROCESS", text)
        self.assertNotIn("Completed project:", text)
        self.assertIn("fake idat2gtc progress", text)  # Raw tool output stays captured.
        self.assertTrue(result.stdout.startswith("SUCCESS: PROJECT completed."))
        self.assert_unlocked()

    def test_json_events_keep_context_and_do_not_duplicate_file_sink(self):
        self.env["LOGSHURU_FORMAT"] = "json"
        other_sink = self.root / "unexpected.log"
        self.env["LOGSHURU_FILE"] = str(other_sink)
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = next(self.logs.glob("*.log")).read_text().splitlines()
        events = [json.loads(line) for line in lines if line.startswith("{")]
        completed = [event for event in events if event["message"] == "Completed project: PROJECT"]
        self.assertEqual(len(completed), 1)
        self.assertEqual(completed[0]["level"], "SUCCESS")
        self.assertEqual(completed[0]["function"], "cleanup")
        self.assertGreater(completed[0]["line"], 0)
        self.assertFalse(other_sink.exists())

    def test_logger_failure_preserves_tool_exit_and_cleanup(self):
        self.env["MOCK_FAIL"] = "+idat2gtc"
        self.env["MOCK_LOG_FAILURE_FLAG"] = str(self.root / "logger-failure")
        date = self.root / "bin/date"
        date.write_text(
            '#!/usr/bin/env bash\n'
            f'if [[ -f "$MOCK_LOG_FAILURE_FLAG" ]]; then exit 73; fi\n'
            f'exec {self.host_date} "$@"\n'
        )
        date.chmod(0o755)
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertIn("FAILED: PROJECT (exit 42). Log:", result.stderr)
        self.assert_unlocked()
        self.assertEqual(len(list(self.data.glob(".PROJECT.idat2vcf.*"))), 1)
        self.assertFalse((self.data / "PROJECT.vcf.gz").exists())

    def test_invalid_logger_configuration_fails_before_acquiring_lock(self):
        self.env["LOG_LEVEL"] = "INVALID"
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("FAILED: PROJECT (exit 1). Log:", result.stderr)
        self.assertIn("Invalid LOG_LEVEL", next(self.logs.glob("*.log")).read_text())
        self.assert_unlocked()

    def test_invalid_arguments_have_no_side_effects(self):
        for args in ((), ("../unsafe",), ("-bad",), ("a", "b"), ("", "PROJECT"),
                     ("--verbose",), ("--unknown", "PROJECT")):
            with self.subTest(args=args):
                self.assertNotEqual(self.run_pipeline(*args).returncode, 0)
        self.assertFalse(self.logs.exists())
        self.assertEqual(self.run_pipeline("--help").returncode, 0)
        help_result = self.run_pipeline("--verbose", "--help")
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("--verbose", help_result.stdout)
        self.assertFalse(self.logs.exists())

    def test_existing_lock_is_preserved(self):
        lock = self.data / ".PROJECT.idat2vcf.lock"
        lock.mkdir()
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.is_dir())
        self.assertIn("Project lock", next(self.logs.glob("*.log")).read_text())
        self.assertIn("FAILED: PROJECT", result.stderr)

    def test_missing_resource(self):
        resource = Path(self.env["IDAT2VCF_RESOURCES_DIR"]) / "GSA-24v3-0_A2.bpm"
        resource.unlink()
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Required file missing", next(self.logs.glob("*.log")).read_text())
        self.assertIn("FAILED: PROJECT", result.stderr)
        self.assert_unlocked()

    def test_empty_inputs_release_lock(self):
        for path in self.inputs.iterdir():
            path.unlink()
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No *_Grn.idat files", next(self.logs.glob("*.log")).read_text())
        self.assertIn("FAILED: PROJECT", result.stderr)
        self.assert_unlocked()

    def test_unpaired_idats_fail_before_conversion(self):
        (self.inputs / "sample_Red.idat").unlink()
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("Unpaired IDAT files: 1 _Grn vs 0 _Red", text)
        self.assertIn("FAILED: PROJECT", result.stderr)
        self.assert_unlocked()
        self.assertEqual(list(self.data.glob(".PROJECT.idat2vcf.*")), [])

    def test_mismatched_names_with_equal_counts_fail_before_conversion(self):
        (self.inputs / "sample_Red.idat").rename(self.inputs / "other_Red.idat")
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("Missing matching Red IDAT for:", text)
        self.assertIn("sample_Grn.idat", text)
        self.assert_unlocked()

    def test_extra_nonstandard_idat_files_warn_but_convert(self):
        (self.inputs / "legacy.idat").write_text("test input\n")
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("1 .idat file(s) do not follow the _Grn/_Red naming", text)
        self.assertIn("| WARNING", text)
        self.assertIn("Found 1 paired IDAT samples (2 files)", text)
        self.assert_unlocked()

    def test_record_count_deviation_warns_without_failing(self):
        self.env["EXPECTED_VCF_RECORDS"] = "2"
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn(
            "Indexed record count 1 differs from the validated count 2", text
        )
        self.assertIn("| WARNING", text)
        self.assertTrue(result.stdout.startswith("SUCCESS: PROJECT completed."))
        # The deviation must be visible in quiet mode, not only in the log.
        self.assertTrue(
            result.stderr.startswith(
                "NOTE: Indexed record count 1 differs from the validated count 2;"
            ),
            result.stderr,
        )
        self.assertTrue(result.stderr.endswith(".log\n"))
        self.assert_unlocked()

    def test_record_count_deviation_strict_mode_fails_before_publication(self):
        self.env["EXPECTED_VCF_RECORDS"] = "2"
        self.env["EXPECTED_VCF_RECORDS_STRICT"] = "1"
        result = self.run_pipeline("PROJECT")
        # 65 = EX_DATAERR, distinguishing a count mismatch from other failures.
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("FAILED: PROJECT (exit 65). Log:", result.stderr)
        text = next(self.logs.glob("*.log")).read_text()
        self.assertIn("differs from the validated count 2", text)
        self.assertIn("EXPECTED_VCF_RECORDS_STRICT is set", text)
        self.assertFalse((self.data / "PROJECT.vcf.gz").exists())
        self.assert_unlocked()

    def test_invalid_expected_record_count_rejected_at_startup(self):
        self.env["EXPECTED_VCF_RECORDS"] = "many"
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("must be a non-negative integer", result.stderr)
        # Rejected before any work: no log directory is created.
        self.assertFalse(self.logs.exists())

    def test_nested_idat_files_fail_preflight_like_the_plugin(self):
        nested = self.inputs / "sub"
        nested.mkdir()
        for channel in ("Grn", "Red"):
            shutil.copyfile(self.inputs / f"sample_{channel}.idat", nested / f"sample_{channel}.idat")
        for path in self.inputs.glob("*.idat"):
            path.unlink()
        result = self.run_pipeline("PROJECT")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "No *_Grn.idat files found", next(self.logs.glob("*.log")).read_text()
        )
        self.assert_unlocked()

    def test_run_log_is_group_and_other_readable(self):
        result = self.run_pipeline("PROJECT")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        mode = stat.S_IMODE(next(self.logs.glob("*.log")).stat().st_mode)
        self.assertEqual(mode, 0o644)


if __name__ == "__main__":
    unittest.main()
