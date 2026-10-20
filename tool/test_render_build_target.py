"""Exercise the real release script with a fake SDK; no network or app build."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class RenderBuildTargetTest(unittest.TestCase):
    def test_component_selects_matching_entrypoint(self):
        source = Path(__file__).resolve().parent
        for component, target in (
            ("admin", "lib/admin/main.dart"),
            ("customer", "lib/main.dart"),
        ):
            with self.subTest(component=component), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "tool").mkdir()
                shutil.copy(source / "build_render_web.sh", root / "tool")
                (root / "tool/stamp_render_web.py").write_text(
                    "import sys\n"
                    "assert sys.argv[1:] == ['build/web', "
                    f"'{component}', '{'a' * 40}']\n"
                )
                sdk = root / "fake-flutter"
                sdk.write_text(
                    "#!/usr/bin/env python3\n"
                    "import os, sys\n"
                    "from pathlib import Path\n"
                    "if sys.argv[1:3] == ['build', 'web']:\n"
                    "    args = sys.argv[1:]\n"
                    "    assert args[args.index('--target') + 1] == os.environ['EXPECTED_TARGET']\n"
                    "    assert '--pwa-strategy=none' in args\n"
                    "    assert '--dart-define=SERVICEPAY_API_BASE_URL=https://api.servicepay.ng/api' in args\n"
                    "    Path('build-ran').touch()\n"
                )
                sdk.chmod(0o755)
                environment = dict(
                    os.environ,
                    FLUTTER_BIN=str(sdk),
                    EXPECTED_TARGET=target,
                    RENDER_GIT_COMMIT="a" * 40,
                )
                subprocess.run(
                    ["bash", "tool/build_render_web.sh", component],
                    cwd=root, env=environment, check=True,
                )
                self.assertTrue((root / "build-ran").is_file())


if __name__ == "__main__":
    unittest.main()
