"""The Laya image tag is overridable in both Compose templates, with the same default.

Laya is the only sidecar in the laya profile without a *_VERSION knob, so a rebuilt Laya image
could only be run by editing compose. These tests keep the knob and its default in step.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TEMPLATES = ("compose.yaml", "deploy/examples/unraid-compose-manager.yml")
DEFAULT = "0.3.5-noevia1"


class LayaImageTagTest(unittest.TestCase):
    def test_each_template_reads_laya_version_with_the_current_default(self):
        for name in TEMPLATES:
            text = (ROOT / name).read_text(encoding="utf-8")
            match = re.search(r"(?m)^  laya:\n(?:    .*\n|\n)*?    image: (\S+)$", text)
            self.assertIsNotNone(match, name)
            self.assertEqual(match.group(1), "cowork-laya:${LAYA_VERSION:-" + DEFAULT + "}", name)

    def test_env_example_documents_the_knob_commented_out(self):
        text = (ROOT / ".env.example").read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^# LAYA_VERSION=" + re.escape(DEFAULT) + r"$")
        self.assertNotRegex(text, r"(?m)^LAYA_VERSION=")


if __name__ == "__main__":
    unittest.main()
