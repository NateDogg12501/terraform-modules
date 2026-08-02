#!/usr/bin/env python3
"""Zip source_dir into output_path with run.sh marked executable (0755).

Exists because hashicorp/archive's archive_file data source zips whatever
permission bits it reads from the host filesystem, and Windows has no concept
of a Unix executable bit for Go's os.Stat to report -- so a zip built by
`terraform apply` on Windows always drops run.sh's +x, and AWS Lambda then
fails to exec it (Lambda Web Adapter's zip-package handler pattern execs
run.sh directly, relying on its shebang line). This script sets the mode
explicitly in the zip's central directory regardless of host OS, so the
result is correct whether built on Windows, macOS, or Linux.
"""
import os
import sys
import zipfile

S_IFREG = 0o100000


def main():
    # Read from env vars, not argv: Terraform's local-exec on Windows
    # corrupts any double-quoted argument in the command string (a stray
    # literal quote survives into the child process's argv), which breaks
    # paths containing spaces. Env vars bypass that shell-quoting path
    # entirely and are set directly on the child process.
    source_dir = os.environ["ZIP_SOURCE_DIR"]
    output_path = os.environ["ZIP_OUTPUT_PATH"]

    if os.path.exists(output_path):
        os.remove(output_path)

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in sorted(os.walk(source_dir)):
            for name in sorted(files):
                full_path = os.path.join(root, name)
                arcname = os.path.relpath(full_path, source_dir).replace(os.sep, "/")

                info = zipfile.ZipInfo(arcname, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if name == "run.sh" else 0o644
                info.external_attr = (S_IFREG | mode) << 16

                with open(full_path, "rb") as f:
                    zf.writestr(info, f.read())


if __name__ == "__main__":
    main()
