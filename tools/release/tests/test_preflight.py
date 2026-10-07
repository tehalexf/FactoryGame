"""What has to be true before a build is worth starting.

Seam: `tools/release/preflight.py`'s `problems(...)`, which takes the facts about
this machine as arguments rather than going and finding them, so every answer here
is a known one. The CLI's job is to do the finding; the judgement is all in that
one function and all of it is tested.

The messages are asserted as well as the verdicts, and that is deliberate. Two
things this preflight blocks can only be fixed **by the human** — `butler login`
and creating the itch project — and a build that stops with "preflight failed" has
helped nobody. So every complaint has to carry the command that answers it, and a
test that only counted the complaints would let that rot.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import preflight  # noqa: E402

REPO = Path(__file__).resolve().parents[3]

ENGINE = "4.7.2.stable"


class _Base(unittest.TestCase):
    """A machine where everything is in order, which each test then spoils."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)

        self.templates = root / "export_templates" / ENGINE
        self.templates.mkdir(parents=True)
        (self.templates / "windows_release_x86_64.exe").write_bytes(b"MZ")
        (self.templates / "version.txt").write_text(ENGINE + "\n")

        self.licensed = root / "quarantine"
        for group in preflight.manifest.expected_bundle(REPO).values():
            for relative in group.files:
                target = self.licensed / Path(relative).relative_to("assets_licensed")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"x")

        self.credentials = root / "butler_creds"
        self.credentials.write_text("{}")

        self.defaults = dict(
            repo_root=REPO,
            licensed_root=self.licensed,
            godot_version=f"{ENGINE}.official.ed1daf0bf",
            templates_root=self.templates.parent,
            butler_on_path=True,
            butler_credentials=self.credentials,
            itch_target="tehalexf/deep-foundry",
            pushing=True,
        )

    def _problems(self, **overrides) -> list[str]:
        return preflight.problems(**{**self.defaults, **overrides})

    def _only(self, **overrides) -> str:
        problems = self._problems(**overrides)
        self.assertEqual(len(problems), 1, problems)
        return problems[0]

    def _said(self, **overrides) -> str:
        """Everything the preflight said, as one block of text."""
        return "\n".join(self._problems(**overrides))


class AMachineThatIsReady(_Base):
    def test_raises_nothing(self) -> None:
        self.assertEqual(self._problems(), [])

    def test_does_not_ask_about_itch_when_only_building(self) -> None:
        self.assertEqual(
            self._problems(pushing=False, butler_on_path=False, itch_target=""), []
        )


class TheToolchain(_Base):
    def test_godot_must_be_on_the_path(self) -> None:
        self.assertIn("godot", self._only(godot_version="").lower())

    def test_export_templates_must_be_installed_for_this_exact_version(self) -> None:
        complaint = self._only(templates_root=Path(self.tmp.name) / "nowhere")
        self.assertIn(ENGINE, complaint)
        self.assertIn("export_templates", complaint)

    def test_the_download_url_is_in_the_message_because_nothing_else_will_do(self) -> None:
        # There is no headless "install templates" command in Godot, so the only
        # useful thing to say is where the .tpz lives and where to unzip it.
        complaint = self._only(templates_root=Path(self.tmp.name) / "nowhere")
        self.assertIn("4.7.2-stable", complaint)
        self.assertIn(".tpz", complaint)

    def test_templates_for_a_different_version_do_not_count(self) -> None:
        # The commonest way this goes wrong: an engine upgrade, and templates for
        # the old one still sitting there.
        complaint = self._only(godot_version="4.9.0.stable.official.abcdef123")
        self.assertIn("4.9.0.stable", complaint)


class TheGeneratedAssets(_Base):
    """The check this whole directory exists for."""

    def test_a_missing_class_stops_the_build(self) -> None:
        bundle = preflight.manifest.expected_bundle(REPO)
        for relative in bundle["audio"].files:
            (self.licensed / Path(relative).relative_to("assets_licensed")).unlink()
        self.assertTrue(any("convert_audio.sh" in p for p in self._problems()))

    def test_the_complaint_names_the_converter_rather_than_the_directory(self) -> None:
        for relative in preflight.manifest.expected_bundle(REPO)["weapons"].files:
            (self.licensed / Path(relative).relative_to("assets_licensed")).unlink()
        said = self._said()
        self.assertIn("bash tools/assets/convert_weapons.sh", said)
        self.assertIn("0 of 3 files present", said)

    def test_one_missing_file_is_as_fatal_as_an_empty_directory(self) -> None:
        # The dangerous case. An empty directory is obvious; a converter that ran
        # before a cue was added to the recipe is not, and the build it produces
        # plays a Kenney fallback for that one cue and says nothing.
        bundle = preflight.manifest.expected_bundle(REPO)["audio"]
        relative = bundle.files[0]
        (self.licensed / Path(relative).relative_to("assets_licensed")).unlink()
        said = self._said()
        self.assertIn("convert_audio.sh", said)
        self.assertIn(relative, said)
        self.assertIn(f"{len(bundle.files) - 1} of {len(bundle.files)}", said)

    def test_an_absent_quarantine_names_all_three_converters(self) -> None:
        problems = self._problems(licensed_root=Path(self.tmp.name) / "nothing")
        joined = "\n".join(problems)
        for converter in ("convert_weapons.sh", "convert_audio.sh", "convert_props.sh"):
            with self.subTest(converter):
                self.assertIn(converter, joined)


class TheThingsOnlyTheHumanCanDo(_Base):
    def test_butler_must_be_installed(self) -> None:
        complaint = self._only(butler_on_path=False)
        self.assertIn("butler", complaint)
        self.assertIn("itch.io/docs/butler", complaint)

    def test_butler_must_be_logged_in_and_the_message_says_so(self) -> None:
        complaint = self._only(butler_credentials=Path(self.tmp.name) / "no_creds")
        self.assertIn("butler login", complaint)

    def test_an_api_key_in_the_environment_counts_as_logged_in(self) -> None:
        # How CI would do it, and the one way this works without a browser.
        self.assertEqual(
            self._problems(
                butler_credentials=Path(self.tmp.name) / "no_creds",
                butler_api_key="an-api-key",
            ),
            [],
        )

    def test_the_itch_project_must_be_named(self) -> None:
        complaint = self._only(itch_target="")
        self.assertIn("ITCH_TARGET", complaint)

    def test_a_target_without_a_slash_is_refused_before_butler_sees_it(self) -> None:
        complaint = self._only(itch_target="deep-foundry")
        self.assertIn("user/game", complaint)

    def test_the_restricted_access_instruction_is_part_of_the_setup(self) -> None:
        # The one piece of advice in here that is not about a command failing, and
        # the reason it is advice rather than a check: nothing can read back how a
        # project's access is configured, so saying it at the moment somebody is
        # creating the project is the only chance to say it at all.
        complaint = self._only(itch_target="")
        self.assertIn("Restricted", complaint)
        self.assertIn("key or in a press list", complaint)

    def test_the_setup_says_why_a_page_password_is_the_wrong_answer(self) -> None:
        # Restricted-plus-keys and public-with-a-password look interchangeable from
        # the itch dashboard. They are not: the itch desktop app cannot open a
        # protected page, and that app's automatic updating is the entire reason to
        # hand a tester an itch build rather than a zip. So the instruction has to
        # rule the wrong one out by name.
        complaint = self._only(itch_target="")
        self.assertIn("password", complaint)
        self.assertIn("desktop app", complaint)
        self.assertIn("updating", complaint)


class TheComplaintsAreOrdered(_Base):
    def test_the_toolchain_is_reported_before_the_assets(self) -> None:
        # Fix order matters when several things are wrong: there is no point
        # cutting 37 audio cues for a build that cannot run the exporter.
        problems = self._problems(
            godot_version="", licensed_root=Path(self.tmp.name) / "nothing"
        )
        self.assertIn("godot", problems[0].lower())


if __name__ == "__main__":
    unittest.main()
