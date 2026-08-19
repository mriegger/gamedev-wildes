import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "compare_performance.py"


class ComparePerformanceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.base_dir = self.root / "base"
        self.candidate_dir = self.root / "candidate"
        self.output_json = self.root / "nested" / "comparison.json"
        self.summary = self.root / "nested" / "summary.md"
        self.base_dir.mkdir()
        self.candidate_dir.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _summary(self, p95_ms: float) -> dict[str, float | int]:
        return {
            "sample_count": 100,
            "mean_ms": p95_ms * 0.7,
            "p50_ms": p95_ms * 0.6,
            "p95_ms": p95_ms,
            "p99_ms": p95_ms * 1.1,
            "max_ms": p95_ms * 1.2,
        }

    def _reports(
        self,
        directory: Path,
        entity_values: list[float] | None = None,
        path_values: list[float] | None = None,
        steady_values: list[float] | None = None,
        streaming_values: list[float] | None = None,
        chunk_build_values: list[float] | None = None,
        chunk_apply_values: list[float] | None = None,
        schema_version: int = 2,
    ) -> None:
        values = {
            "entity_frame": entity_values or [1.0] * 5,
            "bounded_path_search": path_values or [1.0] * 5,
            "steady_game_frame": steady_values or [4.0] * 5,
            "streaming_game_frame": streaming_values or [6.0] * 5,
            "chunk_build": chunk_build_values or [10.0] * 5,
            "chunk_apply": chunk_apply_values or [1.0] * 5,
        }
        for run_number in range(1, 6):
            entity_report = {
                "schema_version": schema_version,
                "benchmark_id": "entity_efficiency",
                "workload": {"seed": 1337, "active_entities": 12},
                "metrics": {
                    "entity_frame": self._summary(values["entity_frame"][run_number - 1]),
                    "bounded_path_search": self._summary(values["bounded_path_search"][run_number - 1]),
                    "spawn_frame": self._summary(0.5),
                    "preparation_frame": self._summary(0.5),
                },
            }
            game_report = {
                "schema_version": schema_version,
                "benchmark_id": "game_performance",
                "workload": {"seed": 1337, "sample_frames": 1200},
                "metrics": {
                    "steady_game_frame": self._summary(values["steady_game_frame"][run_number - 1]),
                    "streaming_game_frame": self._summary(values["streaming_game_frame"][run_number - 1]),
                    "chunk_build": self._summary(values["chunk_build"][run_number - 1]),
                    "chunk_apply": self._summary(values["chunk_apply"][run_number - 1]),
                    "startup": self._summary(1500.0),
                    "streaming_queue_drain": self._summary(800.0),
                },
            }
            (directory / f"entity_efficiency_{run_number}.json").write_text(json.dumps(entity_report), encoding="utf-8")
            (directory / f"game_performance_{run_number}.json").write_text(json.dumps(game_report), encoding="utf-8")

    def _run(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--base-dir",
                str(self.base_dir),
                "--candidate-dir",
                str(self.candidate_dir),
                "--output-json",
                str(self.output_json),
                "--summary",
                str(self.summary),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def _result(self) -> dict:
        return json.loads(self.output_json.read_text(encoding="utf-8"))

    def _metric(self, metric_id: str) -> dict:
        return next(metric for metric in self._result()["metrics"] if metric["metric_id"] == metric_id)

    def test_reports_majority_relative_regression(self) -> None:
        self._reports(self.base_dir)
        self._reports(self.candidate_dir, steady_values=[5.0, 5.0, 5.0, 4.0, 4.0])
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        self.assertIn("::warning title=Performance regression%3A Steady gameplay CPU::", completed.stdout)
        metric = self._metric("steady_game_frame")
        self.assertTrue(metric["relative_regression"])
        self.assertEqual(metric["regressed_runs"], [1, 2, 3])

    def test_includes_unbudgeted_telemetry_without_warning(self) -> None:
        self._reports(self.base_dir)
        self._reports(self.candidate_dir)
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        startup = self._metric("startup")
        spawn = self._metric("spawn_frame")
        self.assertTrue(startup["telemetry_only"])
        self.assertEqual(startup["status"], "telemetry")
        self.assertEqual(spawn["status"], "telemetry")
        self.assertNotIn("Performance regression", completed.stdout)

    def test_suppresses_relative_change_below_noise_floor(self) -> None:
        self._reports(self.base_dir)
        self._reports(self.candidate_dir, entity_values=[1.2] * 5)
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        metric = self._metric("entity_frame")
        self.assertFalse(metric["relative_regression"])
        self.assertEqual(metric["regressed_runs"], [])
        self.assertEqual(metric["status"], "ok")

    def test_two_regressed_pairs_do_not_form_majority(self) -> None:
        self._reports(self.base_dir)
        self._reports(self.candidate_dir, steady_values=[5.0, 5.0, 4.0, 4.0, 4.0])
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        metric = self._metric("steady_game_frame")
        self.assertFalse(metric["relative_regression"])
        self.assertEqual(metric["regressed_runs"], [1, 2])
        self.assertEqual(metric["status"], "ok")

    def test_warns_when_absolute_budget_is_exceeded_without_regression(self) -> None:
        self._reports(self.base_dir, entity_values=[2.1] * 5)
        self._reports(self.candidate_dir, entity_values=[2.1] * 5)
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        self.assertIn("Performance budget exceeded%3A Entity update", completed.stdout)
        metric = self._metric("entity_frame")
        self.assertTrue(metric["budget_miss"])
        self.assertFalse(metric["relative_regression"])
        self.assertEqual(metric["status"], "budget_miss")

    def test_missing_and_malformed_reports_are_non_failing(self) -> None:
        self._reports(self.base_dir)
        self._reports(self.candidate_dir)
        (self.base_dir / "game_performance_2.json").unlink()
        (self.candidate_dir / "entity_efficiency_4.json").write_text("not json", encoding="utf-8")
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        self.assertTrue(self.output_json.is_file())
        self.assertTrue(self.summary.is_file())
        self.assertIn("Performance telemetry unavailable", completed.stdout)
        result = self._result()
        self.assertEqual(result["telemetry_issue_count"], 2)
        self.assertIn("## Telemetry unavailable", self.summary.read_text(encoding="utf-8"))

    def test_schema_mismatch_is_unavailable_and_still_returns_zero(self) -> None:
        self._reports(self.base_dir, schema_version=1)
        self._reports(self.candidate_dir, schema_version=2)
        completed = self._run()
        self.assertEqual(completed.returncode, 0)
        self.assertTrue(self.output_json.is_file())
        result = self._result()
        self.assertEqual(result["telemetry_issue_count"], 10)
        self.assertTrue(all(metric["status"] == "telemetry_unavailable" for metric in result["metrics"]))

    def test_invalid_arguments_return_zero(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0)
        self.assertIn("Performance telemetry unavailable", completed.stdout)


if __name__ == "__main__":
    unittest.main()
