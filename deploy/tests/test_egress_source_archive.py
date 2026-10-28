"""Tampered native image source must fail before any build or extraction."""
import hashlib
import importlib.util
import io
import pathlib
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('egress_archive', ROOT / 'deploy/tools/verify-egress-source-archive.py')
ARCHIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ARCHIVE)


def write(file, entries, prefix=''):
    with tarfile.open(file, 'w:gz') as archive:
        for name, content, mode in entries:
            member = tarfile.TarInfo(prefix + name)
            member.mode = mode
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))


class EgressArchiveTests(unittest.TestCase):
    def check(self, changed, accept=False):
        with tempfile.TemporaryDirectory(prefix='noevia-egress-archive-') as temp:
            expected, source = pathlib.Path(temp) / 'expected.tar', pathlib.Path(temp) / 'source.tar.gz'
            entries = [('Cargo.toml', b'[workspace]\n', 0o644), ('tool.sh', b'#!/bin/sh\n', 0o755)]
            write(expected, entries)
            write(source, changed(entries), 'noevia-rs-reviewed/')
            if accept:
                self.assertEqual(ARCHIVE.verify(expected, source, 'noevia-rs-reviewed'), hashlib.sha256(source.read_bytes()).hexdigest())
            else:
                with self.assertRaises(ValueError):
                    ARCHIVE.verify(expected, source, 'noevia-rs-reviewed')
            self.assertEqual(sorted(p.name for p in pathlib.Path(temp).iterdir()), ['expected.tar', 'source.tar.gz'])

    def test_exact_export_returns_archive_hash_without_extraction(self):
        self.check(lambda entries: entries, True)

    def test_changed_contents_or_executable_bits_rejected(self):
        self.check(lambda entries: [('Cargo.toml', b'bad workspace', 0o644), entries[1]])
        self.check(lambda entries: [entries[0], ('tool.sh', b'#!/bin/sh\n', 0o644)])

    def test_added_removed_duplicate_or_traversal_path_rejected(self):
        self.check(lambda entries: entries + [('extra', b'x', 0o644)])
        self.check(lambda entries: entries[:1])
        self.check(lambda entries: entries + [entries[0]])
        self.check(lambda entries: entries + [('../escape', b'x', 0o644)])


if __name__ == '__main__':
    unittest.main()
