"""Fast, dependency-free unit tests for the simulator's pure row-generation
logic (no DB, no psycopg2 import). See design/Milestones.md M1.3.
"""
import datetime
import unittest

from workflow import build_file, open_state

EXPECTED_ACTION_SEQUENCE = ["APPLICATION_SUBMIT", "LOAN_PROCESS", "SIGNING", "RECORDING"]

EXPECTED_ROLES = {
    "APPLICATION_SUBMIT": ("BORROWER", "LOAN_OFFICER"),
    "LOAN_PROCESS": ("BORROWER", "LOAN_PROCESSOR"),
    "SIGNING": ("BORROWER", "TITLE_AGENT"),
    "RECORDING": ("TITLE_AGENT", None),
}

ROLES = ["BORROWER", "LOAN_OFFICER", "LOAN_PROCESSOR", "TITLE_AGENT", "NOTARY", "COUNTY_RECORDER"]


def make_role_ids(offset=0):
    """A fixture role_ids map, mirroring what simulate.py resolves from the DB
    (a unique person_id/user_id pair per role) before calling build_file."""
    return {
        role: {"person_id": offset + i * 2, "user_id": offset + i * 2 + 1}
        for i, role in enumerate(ROLES)
    }


class BuildFileTests(unittest.TestCase):
    def setUp(self):
        self.base_ts = datetime.datetime(2026, 7, 14, 12, 0, 0, tzinfo=datetime.timezone.utc)
        self.role_ids = make_role_ids()
        self.result = build_file("SIM-0001", self.base_ts, self.role_ids)

    def test_file_is_closed(self):
        self.assertEqual(self.result["file"]["status"], "CLOSED")

    def test_closed_at_matches_terminal_step(self):
        recording = next(a for a in self.result["file_actions"] if a["action_code"] == "RECORDING")
        self.assertEqual(self.result["file"]["closed_at"], recording["received_at"])

    def test_four_actions_in_order(self):
        codes = [a["action_code"] for a in self.result["file_actions"]]
        self.assertEqual(codes, EXPECTED_ACTION_SEQUENCE)

    def test_sent_before_received(self):
        for action in self.result["file_actions"]:
            self.assertLess(action["sent_at"], action["received_at"], action["action_code"])

    def test_terminal_step_has_no_receiver(self):
        recording = next(a for a in self.result["file_actions"] if a["action_code"] == "RECORDING")
        self.assertIsNone(recording["received_user_id"])

    def test_sender_receiver_roles_match_workflow_reference(self):
        role_by_user_id = {ids["user_id"]: role for role, ids in self.role_ids.items()}
        for action in self.result["file_actions"]:
            expected_sender, expected_receiver = EXPECTED_ROLES[action["action_code"]]
            self.assertEqual(role_by_user_id[action["sent_user_id"]], expected_sender, action["action_code"])
            if expected_receiver is not None:
                self.assertEqual(
                    role_by_user_id[action["received_user_id"]], expected_receiver, action["action_code"]
                )

    def test_parties_use_role_ids_person_id(self):
        for party in self.result["parties"]:
            self.assertEqual(party["person_id"], self.role_ids[party["role"]]["person_id"])

    def test_six_parties(self):
        self.assertEqual(len(self.result["parties"]), 6)

    def test_unique_file_number_across_invocations(self):
        other = build_file("SIM-0002", self.base_ts, self.role_ids)
        self.assertNotEqual(self.result["file"]["file_number"], other["file"]["file_number"])


class OpenStateTests(unittest.TestCase):
    """The initial WIP snapshot the lifecycle simulator (M2.8) inserts before
    it UPDATEs the file to its closed state (which is build_file's output)."""

    def setUp(self):
        self.base_ts = datetime.datetime(2026, 7, 14, 12, 0, 0, tzinfo=datetime.timezone.utc)
        self.closed = build_file("SIM-0001", self.base_ts, make_role_ids())
        self.open = open_state(self.closed)

    def test_file_is_wip_and_not_closed(self):
        self.assertEqual(self.open["file"]["status"], "WIP")
        self.assertIsNone(self.open["file"]["closed_at"])

    def test_open_file_keeps_opened_at_and_identity(self):
        self.assertEqual(self.open["file"]["opened_at"], self.closed["file"]["opened_at"])
        self.assertEqual(self.open["file"]["file_number"], self.closed["file"]["file_number"])

    def test_actions_sent_but_not_received(self):
        for action in self.open["file_actions"]:
            self.assertIsNotNone(action["sent_at"], action["action_code"])
            self.assertIsNotNone(action["sent_user_id"], action["action_code"])
            self.assertIsNone(action["received_at"], action["action_code"])
            self.assertIsNone(action["received_user_id"], action["action_code"])

    def test_actions_match_closed_on_sent_fields_and_order(self):
        # The open snapshot differs from the closed state only in the received_*
        # fields (and file status/closed_at) -- sent side and ordering are identical.
        self.assertEqual(
            [a["action_code"] for a in self.open["file_actions"]],
            [a["action_code"] for a in self.closed["file_actions"]],
        )
        for o, c in zip(self.open["file_actions"], self.closed["file_actions"]):
            self.assertEqual(o["sent_at"], c["sent_at"], o["action_code"])
            self.assertEqual(o["sent_user_id"], c["sent_user_id"], o["action_code"])

    def test_parties_unchanged(self):
        self.assertEqual(self.open["parties"], self.closed["parties"])

    def test_does_not_mutate_input(self):
        # open_state must not clobber the closed state it derives from.
        self.assertEqual(self.closed["file"]["status"], "CLOSED")
        self.assertIsNotNone(self.closed["file"]["closed_at"])
        self.assertIsNotNone(self.closed["file_actions"][0]["received_at"])


if __name__ == "__main__":
    unittest.main()
