import contextlib
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import quote, unquote


class AccessLogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).resolve().parents[1] / "app" / "app.py"
        directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(directory.cleanup)
        cls.log_path = Path(directory.name) / "access.log"
        shutil.copy(source.with_name("db.sqlite3"), directory.name)
        # Keep the database and log isolated even on hosts with a /data volume.
        with contextlib.chdir(directory.name), patch("os.path.isdir", return_value=False):
            spec = importlib.util.spec_from_file_location("quoter", source)
            cls.module = importlib.util.module_from_spec(spec)
            with patch.dict(sys.modules, {"quoter": cls.module}):
                spec.loader.exec_module(cls.module)
        cls.addClassCleanup(cls.module.db.close)
        cls.addClassCleanup(cls.module.log_file.close)
        cls.module.app.config["TESTING"] = True

    def setUp(self):
        self.clear_log()
        self.client = self.module.app.test_client()

    def clear_log(self):
        self.module.log_file.seek(0)
        self.module.log_file.truncate()

    def read_log(self):
        return self.log_path.read_bytes().decode("utf-8")

    def test_encoded_controls_cannot_forge_records(self):
        controls = [chr(code) for code in range(32)] + ["\x7f", "\x85", "\u2028", "\u2029"]
        for control in controls:
            with self.subTest(control=repr(control)):
                self.clear_log()
                path = "/missing" + control + "GET /forged"
                response = self.client.get(quote(path, safe="/"))
                self.assertEqual(response.status_code, 404)
                record = self.read_log()
                self.assertEqual(len(record.splitlines()), 1)
                self.assertTrue(record.endswith("\n"))
                self.assertNotIn(control, record[:-1])
                self.assertEqual(unquote(record.removeprefix("GET ").removesuffix("\n")), path)

    def test_ordinary_requests_and_secrets(self):
        self.assertEqual(self.client.get("/").status_code, 200)
        self.client.get("/quotes/1?password=query-secret")
        self.assertEqual(self.client.post("/missing", data={"password": "form-secret"}).status_code, 404)
        self.assertEqual(self.read_log(), "GET /\nGET /quotes/1\nPOST /missing\n")

    def test_literal_escape_is_distinct_from_newline(self):
        self.client.get("/missing%0A")
        self.client.get("/missing%250A")
        self.assertEqual(self.read_log(), "GET /missing%0A\nGET /missing%250A\n")


if __name__ == "__main__":
    unittest.main()
