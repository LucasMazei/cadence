import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fetch_calendar as backend


class BackendTests(unittest.TestCase):
    def test_task_cache_matches_swift_fixture(self):
        fixture = Path(__file__).resolve().parents[2] / "Tests/CadenceTests/Fixtures/task.json"
        task = {"id": "t", "title": "Example", "due": "2026-01-01T00:00:00Z", "status": "needsAction"}
        self.assertEqual(backend.task_object({"id": "work"}, {"id": "inbox"}, task), json.loads(fixture.read_text()))

    def test_tokens_are_private_before_and_after_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token.json"
            account = {"id": "test", "tokenPath": str(token)}
            settings = {"cacheDirectory": directory}
            backend.write_json(token, {"scopes": []})
            token.chmod(0o644)
            creds = Mock(valid=False, expired=True, refresh_token=True)
            creds.refresh.side_effect = lambda _: setattr(creds, "valid", True)
            creds.to_json.return_value = '{"scopes": ["scope"]}'
            with patch.object(backend.Credentials, "from_authorized_user_file", return_value=creds):
                backend.authenticate(settings, account, ["scope"])
            self.assertEqual(stat.S_IMODE(token.stat().st_mode), 0o600)
            self.assertEqual(json.loads(token.read_text()), {"scopes": ["scope"]})

    def test_failed_account_preserves_successful_accounts(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = {"cacheDirectory": directory, "accounts": [
                {"id": name, "calendar": True} for name in ("missing", "working")
            ]}
            with patch.object(backend, "authenticate", side_effect=[RuntimeError(), object()]), \
                 patch.object(backend, "get_upcoming_events", return_value=[{"id": "example"}]):
                backend.sync(settings)
            self.assertEqual(json.loads((Path(directory) / "events.json").read_text()), [{"id": "example"}])
