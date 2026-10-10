"""What the exported build is required to contain, and how absence is reported.

Seam: `tools/release/manifest.py`'s two public functions — `expected_bundle`,
which answers "which files must be in the PCK", and `audit`, which answers "which
are missing and what do I run to get them". Nothing here reaches into the parsing.

The expected set is **derived from the three converters themselves**, which are
committed and are the recipes (docs/ASSET_PIPELINE.md §7-9). A hand-written list
would drift the first time someone added a cue, and a drifted list is exactly the
silently-degraded build this whole directory exists to prevent.

Two kinds of test here, deliberately:

* against the **real** converters, asserting known-good facts about them — the
  weapons the recipe names, a cue it cuts, the manifest the prop converter writes;
* against **fixture** recipes in a temporary directory, which is where the parsing
  is pinned down, because a fixture is an independent source of truth and the real
  file is not.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manifest  # noqa: E402

REPO = Path(__file__).resolve().parents[3]


class ExpectedBundleAgainstTheRealConverters(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = manifest.expected_bundle(REPO)

    def test_the_three_runtime_asset_classes_are_all_declared(self) -> None:
        self.assertEqual(sorted(self.bundle), ["audio", "props", "weapons"])

    def test_every_class_names_the_converter_that_produces_it(self) -> None:
        for name, group in self.bundle.items():
            with self.subTest(name):
                self.assertIn("tools/assets/convert_", group.converter)

    def test_weapons_are_the_three_the_recipe_frames(self) -> None:
        # convert_weapons.sh's header says which FBX becomes which weapon.
        self.assertEqual(
            sorted(self.bundle["weapons"].files),
            [
                "assets_licensed/generated/gear/bolt_rifle.glb",
                "assets_licensed/generated/gear/drum_autocannon.glb",
                "assets_licensed/generated/gear/pneumatic_wrench.glb",
            ],
        )

    def test_audio_includes_a_cue_the_recipe_cuts(self) -> None:
        self.assertIn(
            "assets_licensed/generated/audio/silo_commit.ogg", self.bundle["audio"].files
        )

    def test_audio_is_the_whole_catalogue_rather_than_a_sample(self) -> None:
        # Every cue the recipe declares is in the bundle, and the bundle holds
        # nothing that is not one. Coverage is the claim: a parse that quietly
        # matched half of them would still look plausible.
        #
        # **A cue is not a file.** `--takes N` writes `name.ogg` *plus*
        # `name_2.ogg` … `name_N.ogg`, so a cue with takes contributes several and a
        # count of `cue` lines is the wrong total — which is exactly the bug this
        # caught in `audio_files`. The recipe's arithmetic is not redone here,
        # because this class does not reach into the parsing and
        # `ParsingIsPinnedAgainstFixtureRecipes` pins it against a fixture. What is
        # asserted instead is the shape: every declared cue is present, every extra
        # file is a numbered take of a declared cue, and there are extras.
        declared = {
            line.split()[1]
            for line in (REPO / "tools/assets/convert_audio.sh").read_text().splitlines()
            if line.startswith("cue ") and len(line.split()) > 1
        }
        self.assertGreater(len(declared), 20, "the recipe is not a stub")

        stems = {Path(path).stem for path in self.bundle["audio"].files}
        self.assertEqual(
            set(), declared - stems, "cues the recipe cuts but the bundle omits"
        )

        takes = stems - declared
        for stem in sorted(takes):
            with self.subTest(stem):
                base, _, number = stem.rpartition("_")
                self.assertIn(
                    base, declared, "a file in the bundle that is nobody's cue"
                )
                self.assertTrue(number.isdigit(), "an extra file is a numbered take")
                self.assertGreaterEqual(
                    int(number), 2, "take 1 keeps the unnumbered name"
                )
        self.assertTrue(takes, "several cues have more than one take; see #35")

    def test_props_carry_the_shared_atlas_and_the_conversion_record(self) -> None:
        files = self.bundle["props"].files
        self.assertIn("assets_licensed/generated/props/atlas.png", files)
        self.assertIn("assets_licensed/generated/props/atlas_glow.png", files)
        self.assertIn("assets_licensed/generated/props/props.json", files)

    def test_props_are_the_catalogue_the_set_dressing_asks_for(self) -> None:
        sys.path.insert(0, str(REPO / "tools" / "assets"))
        import convert_props  # noqa: PLC0415

        glbs = [f for f in self.bundle["props"].files if f.endswith(".glb")]
        self.assertEqual(len(glbs), len(convert_props.CATALOGUE))

    def test_nothing_is_expected_outside_the_quarantine(self) -> None:
        # A bundled path that escaped `assets_licensed/generated/` would be a path
        # the licence guard has an opinion about.
        for group in self.bundle.values():
            for path in group.files:
                with self.subTest(path):
                    self.assertTrue(path.startswith("assets_licensed/generated/"))


class AuditReportsWhatIsMissingAndHowToFixIt(unittest.TestCase):
    """`audit` against a quarantine we build by hand, so the answer is known."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.licensed = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def _generate(self, bundle: dict) -> None:
        for group in bundle.values():
            for relative in group.files:
                target = self.licensed / Path(relative).relative_to("assets_licensed")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"x")

    def test_a_complete_quarantine_audits_clean(self) -> None:
        bundle = manifest.expected_bundle(REPO)
        self._generate(bundle)
        self.assertEqual(manifest.audit(REPO, self.licensed), [])

    def test_an_empty_quarantine_faults_every_class_by_name(self) -> None:
        problems = manifest.audit(REPO, self.licensed)
        self.assertEqual(len(problems), 3)
        for problem in problems:
            with self.subTest(problem.name):
                self.assertEqual(problem.present, 0)
                self.assertGreater(problem.expected, 0)

    def test_a_fault_quotes_the_converter_to_run(self) -> None:
        problems = {p.name: p for p in manifest.audit(REPO, self.licensed)}
        self.assertIn("convert_audio.sh", problems["audio"].converter)
        self.assertIn("convert_weapons.sh", problems["weapons"].converter)
        self.assertIn("convert_props.sh", problems["props"].converter)

    def test_one_missing_cue_is_a_fault_and_is_named(self) -> None:
        # The failure mode that matters: not an empty directory, which anyone would
        # notice, but a converter that ran before a cue was added to the recipe.
        bundle = manifest.expected_bundle(REPO)
        self._generate(bundle)
        (self.licensed / "generated/audio/silo_commit.ogg").unlink()

        problems = manifest.audit(REPO, self.licensed)
        self.assertEqual([p.name for p in problems], ["audio"])
        self.assertEqual(
            problems[0].missing, ["assets_licensed/generated/audio/silo_commit.ogg"]
        )

    def test_a_zero_byte_file_does_not_count_as_present(self) -> None:
        bundle = manifest.expected_bundle(REPO)
        self._generate(bundle)
        (self.licensed / "generated/gear/bolt_rifle.glb").write_bytes(b"")

        problems = manifest.audit(REPO, self.licensed)
        self.assertEqual([p.name for p in problems], ["weapons"])


class ParsingIsPinnedAgainstFixtureRecipes(unittest.TestCase):
    """The recipes are shell and Python; this is where their dialects are read."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        (self.root / "tools/assets").mkdir(parents=True)

    def _recipe(self, name: str, body: str) -> None:
        (self.root / "tools/assets" / name).write_text(body)

    def test_weapon_outputs_are_read_off_the_output_flag(self) -> None:
        self._recipe(
            "convert_weapons.sh",
            'convert x \\\n    --output "$out_dir/sidearm.glb" \\\n'
            '    --rotate 0\nconvert y --output "$out_dir/mallet.glb"\n'
            '# --output "$out_dir/commented_out.glb"\n',
        )
        self.assertEqual(
            manifest.weapon_files(self.root),
            [
                "assets_licensed/generated/gear/mallet.glb",
                "assets_licensed/generated/gear/sidearm.glb",
            ],
        )

    def test_cue_lines_are_read_and_continuations_and_comments_are_not(self) -> None:
        self._recipe(
            "convert_audio.sh",
            'cue klaxon "SomeLibrary_Horn" --duration 1.0\n'
            "cue  not_a_cue_because_of_spacing\n"
            '# cue commented "X"\n'
            'cue bell "Church Bells" \\\n  --semitones -4\n'
            '  --search 0:4\ncue klaxon "duplicate declaration"\n',
        )
        self.assertEqual(
            manifest.audio_files(self.root),
            [
                "assets_licensed/generated/audio/bell.ogg",
                "assets_licensed/generated/audio/klaxon.ogg",
            ],
        )

    def test_takes_are_counted_as_the_several_files_they_are(self) -> None:
        # `--takes N` writes N files and take 1 keeps the unnumbered name, so the
        # bundle has to expect `swing.ogg`, `swing_2.ogg`, `swing_3.ogg` — not one
        # `swing.ogg` and a silent gap where the variance went. A build missing
        # `swing_3.ogg` would still run, still play a swing, and sound exactly like
        # the one-take cue #35 was filed about, which is why this is verified.
        #
        # The flag sits on the **continuation**, which is how it went unread: a
        # declaration spread over three lines is one declaration.
        self._recipe(
            "convert_audio.sh",
            'cue swing "Some_Tool" \\\n  --takes 3 --duration 0.4\n'
            'cue single "Some_Bell" --duration 1.0\n'
            'cue two "Some_Door" --takes 2\n',
        )
        self.assertEqual(
            manifest.audio_files(self.root),
            [
                "assets_licensed/generated/audio/single.ogg",
                "assets_licensed/generated/audio/swing.ogg",
                "assets_licensed/generated/audio/swing_2.ogg",
                "assets_licensed/generated/audio/swing_3.ogg",
                "assets_licensed/generated/audio/two.ogg",
                "assets_licensed/generated/audio/two_2.ogg",
            ],
        )


if __name__ == "__main__":
    unittest.main()
