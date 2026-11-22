"""Guard the BuildStream cache refill restore keys.

The refill workflow must reuse a usable older cache for the same architecture
when the cache for the current inputs does not exist. It does this by asking
actions/cache/restore to try the exact current-input key first and then fall
back to the architecture prefix. If the fallback is missing, an ARM64 refill
whose inputs changed starts cold even though an older ARM64 cache exists, and
the next refill repeats the hour-long cold build.

This check reads the real workflow and asserts the restore-keys list both
tokens in that order: the exact-input prefix, then the architecture prefix.
It fails against a workflow that only lists the exact-input prefix.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/bst-cache.yml"

EXACT_INPUT = "${{ steps.cache-key.outputs.inputs }}"
ARCH_PREFIX = "${{ env.CACHE_PREFIX }}"


def restore_key_lines():
    """Return the non-empty restore-keys lines of the Restore step, top to bottom."""
    workflow = yaml.load(WORKFLOW.read_text(), Loader=yaml.BaseLoader)
    step = next(
        s
        for s in workflow["jobs"]["refill"]["steps"]
        if s.get("name") == "Restore BuildStream cache"
    )
    keys = step["with"]["restore-keys"]
    return [line.strip() for line in keys.splitlines() if line.strip()]


class RestoreKeyTests(unittest.TestCase):
    def test_restore_keys_have_exact_input_then_architecture_prefix(self):
        # The regression this guard exists for: a workflow that lists only the
        # exact-input prefix passes nothing to fall back on. This assertion
        # fails against that workflow and passes once the fallback is added.
        self.assertEqual(
            restore_key_lines(),
            [EXACT_INPUT, ARCH_PREFIX],
            "restore-keys must list the exact-input prefix first, then the "
            "architecture-prefix fallback",
        )

    def test_architecture_prefix_fallback_present(self):
        lines = restore_key_lines()
        self.assertIn(ARCH_PREFIX, lines)
        self.assertEqual(lines[0], EXACT_INPUT,
                         "exact-input prefix must keep top preference")
        self.assertEqual(lines.index(ARCH_PREFIX), 1,
                         "architecture prefix must follow the exact-input prefix")

    def test_no_extra_restore_tokens(self):
        self.assertEqual(len(restore_key_lines()), 2)


if __name__ == "__main__":
    unittest.main()
