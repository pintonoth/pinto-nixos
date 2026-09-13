"""Exercise installer command plans with shell functions replacing disk tools.

Run: python3 -m unittest discover -s tests -v
No root privileges or real disk operations are used.
"""
import pathlib
import subprocess
import unittest


SCRIPT = (pathlib.Path(__file__).resolve().parents[1] / "install.sh").read_text()
FUNCTIONS = SCRIPT.split('if [[ ${1:-} == --help', 1)[0]


def run_shell(body, stdin=""):
    return subprocess.run(
        ["bash", "-c", FUNCTIONS + "\n" + body],
        input=stdin, text=True, capture_output=True,
    )


class InstallerTests(unittest.TestCase):
    def test_partition_names(self):
        result = run_shell('''
for disk in /dev/sda /dev/nvme0n1 /dev/mmcblk0; do
  partition_path "$disk" 2
  printf '\n'
done
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "/dev/sda2", "/dev/nvme0n1p2", "/dev/mmcblk0p2",
        ])

    def test_layouts(self):
        for fs in ("ext4", "xfs", "btrfs"):
            for swap in (0, 8, 16):
                with self.subTest(fs=fs, swap=swap):
                    result = run_shell('''
parted() { printf '%s\n' "$*"; }
partprobe() { printf 'probe %s\n' "$*"; }
udevadm() { printf 'udev %s\n' "$*"; }
''' + f'partition_disk /dev/nvme0n1 {fs} {swap}\n')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    prefix = "--script /dev/nvme0n1 -- "
                    expected = [prefix + "mklabel gpt"]
                    end = f"-{swap}GiB" if swap else "100%"
                    expected += [prefix + f"mkpart root {fs} 512MiB {end}"]
                    if swap:
                        expected += [prefix + f"mkpart swap linux-swap {end} 100%"]
                    expected += [
                        prefix + "mkpart ESP fat32 1MiB 512MiB",
                        prefix + f"set {3 if swap else 2} esp on",
                        "probe /dev/nvme0n1", "udev settle",
                    ]
                    self.assertEqual(result.stdout.splitlines(), expected)

    def test_partition_failure_stops(self):
        result = run_shell('''
parted() { return 42; }
partprobe() { echo SHOULD_NOT_RUN; }
udevadm() { echo SHOULD_NOT_RUN; }
partition_disk /dev/fake ext4 0
echo SHOULD_NOT_RUN
''')
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("SHOULD_NOT_RUN", result.stdout)

    def test_skip_does_not_prepare_disk(self):
        result = run_shell('''
lsblk() { :; }
check_unused_disk() { echo SHOULD_NOT_RUN; exit 99; }
partition_disk() { echo SHOULD_NOT_RUN; exit 99; }
prepare_storage
''', "1\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("SHOULD_NOT_RUN", result.stdout)

    def test_selection_eof_aborts(self):
        result = run_shell('lsblk() { :; }; prepare_storage')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No disk selected", result.stderr)

    def test_wrong_erasure_confirmation_aborts(self):
        result = run_shell('''
lsblk() {
  case "$1" in
    -dnpo) echo '/dev/fake disk' ;;
    -bdnro) echo 107374182400 ;;
  esac
}
check_unused_disk() { :; }
findmnt() { :; }
swapon() { :; }
parted() { echo SHOULD_NOT_RUN; }
partprobe() { echo SHOULD_NOT_RUN; }
udevadm() { echo SHOULD_NOT_RUN; }
mkfs.ext4() { echo SHOULD_NOT_RUN; }
mkfs.fat() { echo SHOULD_NOT_RUN; }
mount() { echo SHOULD_NOT_RUN; }
prepare_storage
''', "1\n\nn\n/dev/wrong\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cancelled before erasing", result.stderr)
        self.assertNotIn("SHOULD_NOT_RUN", result.stdout)


if __name__ == "__main__":
    unittest.main()
