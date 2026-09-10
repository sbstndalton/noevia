import unittest
from unittest.mock import patch
import server
class BridgeTests(unittest.TestCase):
    def test_initialization_and_tool_permissions(self):
        result=server.dispatch({'method':'initialize'},{});self.assertIn('tools',result['capabilities'])
        tools=server.dispatch({'method':'tools/list'}, {})['tools']
        self.assertFalse(tools[-1]['annotations']['readOnlyHint']);self.assertIn('version',tools[-1]['inputSchema']['required'])
    def test_errors_preserve_unconfirmed_writes_without_retries(self):
        with patch('server.call',side_effect=ValueError('Conflict: reread')) as call:
            result=server.dispatch({'method':'tools/call','params':{'name':'diary_write','arguments':{}}},{})
            self.assertTrue(result['isError']);self.assertEqual(call.call_count,1)
    def test_http_destinations_rejected(self):
        with self.assertRaises(ValueError):server.call('diary_read',{'path':'a.md'},{'url':'http://untrusted/api/diary-connector','token':'synthetic'})
if __name__=='__main__':unittest.main()
