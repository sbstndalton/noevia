#!/usr/bin/env python3
"""Bind the native image tarball input to the exact reviewed Git export, without extraction."""
import hashlib
import pathlib
import sys
import tarfile


def exported(tar, prefix=None):
    result = {}
    for member in tar.getmembers():
        name = member.name.rstrip('/')
        if prefix is not None:
            if name == prefix and member.isdir():
                continue
            if not name.startswith(prefix + '/'):
                raise ValueError('unexpected archive root')
            name = name[len(prefix) + 1:]
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path) != name or name in result:
            raise ValueError('invalid or repeated source path')
        if member.isfile():
            kind = ('file', member.mode & 0o111, member.size)
        elif member.isdir():
            kind = ('directory',)
        elif member.issym():
            kind = ('symlink', member.linkname)
        else:
            raise ValueError('unsupported source entry')
        result[name] = (kind, member)
    return result


def verify(expected_file, source_file, prefix):
    with tarfile.open(expected_file) as expected, tarfile.open(source_file) as source:
        left, right = exported(expected), exported(source, prefix)
        if left.keys() != right.keys():
            raise ValueError('source path set differs from reviewed export')
        for name, (kind, member) in left.items():
            actual_kind, actual = right[name]
            if kind != actual_kind:
                raise ValueError('source type, executable mode, size or link differs')
            if member.isfile():
                with expected.extractfile(member) as a, source.extractfile(actual) as b:
                    if hashlib.file_digest(a, 'sha256').digest() != hashlib.file_digest(b, 'sha256').digest():
                        raise ValueError('source content differs from reviewed export')
    with open(source_file, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit('usage: verify-egress-source-archive.py <git-export.tar> <github.tar.gz> <github-root>')
    try:
        print(verify(*sys.argv[1:]))
    except (ValueError, tarfile.TarError, OSError):
        sys.exit('native image source archive does not match the reviewed Git export')
