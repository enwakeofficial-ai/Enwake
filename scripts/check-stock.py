import sqlite3,json,tempfile,os,concurrent.futures,pathlib
migration=next(pathlib.Path('drizzle').glob('*.sql')).read_text()
fd,path=tempfile.mkstemp(suffix='.sqlite');os.close(fd)
try:
 d=sqlite3.connect(path);d.executescript(migration)
 d.execute("INSERT INTO products VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",('c','Candle','Candles','Woody','','',10000,10000,3,'200g','','/images/x.webp',-1,1,0,'',1));d.commit()
 def create(id,qty,price=10000):
  conn=sqlite3.connect(path,timeout=10)
  try:
   item=json.dumps([dict(id='c',quantity=qty,price=price)])
   row=(id,id,'private',None,'Test','test@example.com','9999999999','Test street','Test','Test','500001','',item,qty*price,0,0,qty*price,'','New','Preview','preview',None,None,'',1)
   conn.execute('INSERT INTO orders VALUES('+','.join('?' for _ in row)+')',row);conn.commit();return True
  except sqlite3.IntegrityError:conn.rollback();return False
  finally:conn.close()
 with concurrent.futures.ThreadPoolExecutor(2) as pool:result=list(pool.map(lambda i:create(str(i),2),range(2)))
 assert sum(result)==1,'Concurrent orders oversold stock'
 assert d.execute("SELECT stock FROM products WHERE id='c'").fetchone()[0]==1
 winner=str(result.index(True));d.execute("UPDATE orders SET status='Cancelled' WHERE id=?",(winner,));d.commit()
 assert d.execute("SELECT stock FROM products WHERE id='c'").fetchone()[0]==3
 d.execute("UPDATE orders SET status='Cancelled' WHERE id=?",(winner,));d.commit()
 assert d.execute("SELECT stock FROM products WHERE id='c'").fetchone()[0]==3,'Cancellation restored twice'
 assert not create('bad-price',1,1),'Stale/tampered price accepted'
 assert not create('too-many',4),'Oversized quantity accepted'
 assert create('one',1)
 assert not create('one',1),'Duplicate request accepted'
 assert d.execute("SELECT stock FROM products WHERE id='c'").fetchone()[0]==2,'Retry changed stock'
 print('Database checks passed: concurrent stock, cancellation, stale pricing and idempotency.')
finally:
 d.close();os.remove(path)
