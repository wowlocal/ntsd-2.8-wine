"""Wine +timestamp,+bitblt frame spacing; timestamp resolution is 1 ms."""
import argparse,re,collections,csv,json,statistics
from pathlib import Path
pat=re.compile(r'^(\d+)\.(\d+):([0-9a-f]+):trace:bitblt:NtGdiStretchBlt src (0x[0-9a-f]+).*? dst (0x[0-9a-f]+) log=(-?\d+),(-?\d+) (\d+)x(\d+).*?rop=([0-9a-f]+)')
def read(p):
 rows=[]
 with p.open(errors='replace') as f:
  for line in f:
   m=pat.match(line)
   if not m:continue
   sec,ms,thread,src,dst,x,y,w,h,rop=m.groups();rows.append(dict(t_ms=int(sec)*1000+int(ms.ljust(3,'0')[:3]),thread=thread,src=src,dst=dst,x=int(x),y=int(y),w=int(w),h=int(h),rop=rop))
 return rows

def quantile(a,q):
 s=sorted(a);x=(len(s)-1)*q;i=int(x);j=min(i+1,len(s)-1);return s[i]+(s[j]-s[i])*(x-i)
def summary(t):
 d=[b-a for a,b in zip(t,t[1:])];assert d and min(d)>=0
 return dict(frames=len(t),intervals=len(d),duration_s=(t[-1]-t[0])/1000,average_fps=1000*len(d)/(t[-1]-t[0]),mean_ms=statistics.mean(d),p50_ms=quantile(d,.5),p95_ms=quantile(d,.95),p99_ms=quantile(d,.99),max_ms=max(d),over50=sum(x>50 for x in d),over100=sum(x>100 for x in d),timestamp_resolution_ms=1)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('file',type=Path);ap.add_argument('--dst');ap.add_argument('--start',type=float,default=0);ap.add_argument('--end',type=float,default=float('inf'));ap.add_argument('--out',type=Path);a=ap.parse_args();rows=read(a.file)
 print('largest-copy streams',collections.Counter((r['dst'],r['w'],r['h'],r['rop']) for r in rows if r['w']>=1000 and r['h']>=600).most_common(8))
 print('latest', rows[-1] if rows else None)
 if not a.dst:return
 rr=[r for r in rows if r['dst']==a.dst and r['w']>=1000 and r['h']>=600 and a.start*1000<=r['t_ms']<=a.end*1000]
 t=[r['t_ms'] for r in rr];result=summary(t);result.update(dst=a.dst,start_s=t[0]/1000,end_s=t[-1]/1000,source=str(a.file));print(json.dumps(result,indent=2))
 if a.out:
  with a.out.with_suffix('.csv').open('w') as f:
   wr=csv.writer(f,lineterminator="\n");wr.writerow(['timestamp_s','relative_s','frame_ms','source_dc','destination_dc','width','height'])
   for prev,r in zip(rr,rr[1:]):wr.writerow([r['t_ms']/1000,(r['t_ms']-t[0])/1000,r['t_ms']-prev['t_ms'],r['src'],r['dst'],r['w'],r['h']])
  a.out.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
