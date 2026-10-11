"""Runs only in fresh temporary directories, with an injected fake chat transport."""
import base64, io, json, sqlite3, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, '/root/rhysel/alcove-backend')
from PIL import Image
from embroidery_store import Store
from embroidery_api import deliver

class EmbroideryTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.store=Store(self.root/'works')
        b=io.BytesIO();Image.new('RGB',(30,20),'#dddddd').save(b,format='PNG');self.png='data:image/png;base64,'+base64.b64encode(b.getvalue()).decode()
        self.doc={'id':'emb_fake_1','author':'ji','fabric':'cotton','shape':{'kind':'rect','w':800,'h':460},'layers':[],'version':1}
        self.chat=self.root/'chat.db'
        with sqlite3.connect(self.chat) as db: db.execute('CREATE TABLE messages(id INTEGER PRIMARY KEY,role TEXT,text TEXT,attachment_url TEXT,attachment_type TEXT,attachment_filename TEXT)')
        self.count=0
    def tearDown(self):self.temp.cleanup()
    def fake(self,endpoint,payload):
        self.count+=1
        with sqlite3.connect(self.chat) as db: db.execute('INSERT INTO messages(role,text) VALUES(?,?)',(payload['role'],payload['text']))
        return {'ok':True}
    def test_finish_freeze_and_quilt(self):
        first=self.store.finish(self.doc,self.png);again=self.store.finish(self.doc,self.png)
        self.assertEqual(first['finished_at'],again['finished_at']);self.assertEqual(len(self.store.quilt()),1)
        with self.assertRaises(ValueError):self.store.finish(dict(self.doc,title='changed'),self.png)
        new=dict(self.doc,id='emb_fake_2',parent=first['id'])
        with self.assertRaises(ValueError):self.store.finish(new,self.png)
        self.store.finish(new,self.png,quilt_action='replace');self.assertEqual(self.store.quilt()[0]['id'],new['id']);self.assertEqual(self.store.get(first['id'])['id'],first['id'])
    def test_trash_restore(self):
        self.store.finish(self.doc,self.png);self.store.trash(self.doc['id']);self.assertEqual(self.store.quilt(),[]);self.assertEqual(len(self.store.list(trash=True)),1);self.store.trash(self.doc['id'],True);self.assertEqual(len(self.store.quilt()),1)
    def test_send_idempotent(self):
        self.store.finish(self.doc,self.png)
        cb=lambda d,p:deliver(d,p,self.chat,self.root/'attachments',self.fake)
        first=self.store.send(self.doc['id'],cb);self.assertEqual(first,self.store.send(self.doc['id'],cb));self.assertEqual(self.count,1)
        with sqlite3.connect(self.chat) as db:
            row=db.execute('SELECT text,attachment_url FROM messages').fetchone();self.assertIn('EMBROIDERY_CARD',row[0]);self.assertTrue(row[1].endswith('.png'))
    def test_uncertain_never_reinjects(self):
        self.store.finish(self.doc,self.png)
        def timeout(d,p):raise TimeoutError()
        with self.assertRaises(TimeoutError):self.store.send(self.doc['id'],timeout)
        with self.assertRaises(ValueError):self.store.send(self.doc['id'],lambda d,p:self.fail('must not retry'))
    def test_reconcile_existing(self):
        doc=self.store.finish(self.doc,self.png);p=self.store.png(doc['id'])
        deliver(doc,p,self.chat,self.root/'attachments',self.fake);deliver(doc,p,self.chat,self.root/'attachments',self.fake);self.assertEqual(self.count,1)
    def test_lost_response_reconciles_without_resend(self):
        doc=self.store.finish(self.doc,self.png)
        def lost(d,p):
            deliver(d,p,self.chat,self.root/'a',self.fake)
            raise TimeoutError()
        with self.assertRaises(TimeoutError):self.store.send(doc['id'],lost)
        result=self.store.send(doc['id'],lambda d,p:self.fail('must not deliver'),reconcile=lambda d,p:deliver(d,p,self.chat,self.root/'a',lookup_only=True))
        self.assertTrue(result['ok']);self.assertEqual(self.count,1)
    def test_reject_external_photo(self):
        d=dict(self.doc,layers=[{'id':'bad','type':'image','src':'http://127.0.0.1/private'}])
        with self.assertRaises(ValueError):self.store.finish(d,self.png)
    def test_jing_uses_append(self):
        d=self.store.finish(self.doc,self.png,author='jing')
        def transport(endpoint,payload):
            self.assertEqual(endpoint,'/chat/append');self.assertEqual(payload['role'],'assistant');return self.fake(endpoint,payload)
        self.store.send(d['id'],lambda d,p:deliver(d,p,self.chat,self.root/'a',transport))

if __name__=='__main__':unittest.main()
