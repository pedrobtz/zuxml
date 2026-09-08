#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zux.h"

static long tick, cancel_at;
static zux_status t(void){ tick++; return (cancel_at>0 && tick==cancel_at)?ZUX_ERR_CANCELLED:ZUX_OK; }
static zux_status hs(void*c,const zux_name*n,const zux_attr*a,size_t k){(void)c;(void)n;(void)a;(void)k;return t();}
static zux_status he(void*c,const zux_name*n){(void)c;(void)n;return t();}
static zux_status ht(void*c,zux_str s){(void)c;(void)s;return t();}
static zux_status hc(void*c,zux_str s){(void)c;(void)s;return t();}
static zux_status hp(void*c,zux_str a,zux_str b){(void)c;(void)a;(void)b;return t();}
static zux_status hd(void*c,zux_str a,zux_str b,int s){(void)c;(void)a;(void)b;(void)s;return t();}

static zux_status run(const char*doc,size_t chunk,long cancel,zux_options*o){
  zux_parser*p=NULL; zux_handlers h; zux_error e; zux_status st; size_t i,n=strlen(doc);
  memset(&h,0,sizeof h);
  h.start_element=hs;h.end_element=he;h.text=ht;h.comment=hc;h.pi=hp;h.xml_decl=hd;
  tick=0; cancel_at=cancel;
  st=zux_parser_new(&p,o,&h,NULL);
  if(st!=ZUX_OK) return st;
  if(chunk==0)chunk=n?n:1;
  for(i=0;i<n;i+=chunk){size_t k=(n-i<chunk)?n-i:chunk; st=zux_parser_feed(p,doc+i,k); if(st!=ZUX_OK)break;}
  if(st==ZUX_OK) st=zux_parser_finish(p);
  zux_parser_error(p,&e);
  zux_parser_free(p);
  return st;
}

int main(void){
  static const char*docs[]={
    "<a/>","<p>Hi <em>X</em> there</p>","<a><![CDATA[x<y]]>t</a>",
    "<f:a xmlns:f=\"urn:a\" xmlns=\"urn:d\"><b id=\"1\">t</b></f:a>",
    "<?xml version=\"1.0\"?><a><!--c--><?p d?>t&amp;u</a>",
    "<a>naive cafe \xe4\xb8\xad\xe6\x96\x87 \xf0\x9f\x98\x80</a>",
    "<a><b></a>","<a>","<!DOCTYPE a [<!ENTITY e \"X\">]><a>&e;</a>",
    "<a>&nbsp;</a>","not xml","", "<a xmlns=\"urn:a&#12;b\"/>"};
  size_t nd=sizeof docs/sizeof*docs, i, c;
  size_t chunks[]={0,1,2,3,7,31,4096};
  zux_options o; long k;
  long total=0;

  for(i=0;i<nd;i++)
    for(c=0;c<sizeof chunks/sizeof*chunks;c++){
      zux_options_init(&o); run(docs[i],chunks[c],0,&o); total++;
      zux_options_init(&o); o.allow_doctype=1; run(docs[i],chunks[c],0,&o); total++;
      for(k=1;k<=12;k++){ zux_options_init(&o); run(docs[i],chunks[c],k,&o); total++; }
    }
  /* every limit, on input designed to trip it */
  { char big[200000]; memset(big,'x',sizeof big-1); big[sizeof big-1]=0;
    size_t dn=sizeof big+16; char *d=malloc(dn); snprintf(d,dn,"<a>%s</a>",big);
    zux_options_init(&o); o.max_text=100;    run(d,7,0,&o); total++;
    zux_options_init(&o); o.max_memory=4096; run(d,7,0,&o); total++;
    free(d); }
  { char deep[8000]; size_t j; deep[0]=0;
    for(j=0;j<100;j++) strcat(deep,"<a>");
    for(j=0;j<100;j++) strcat(deep,"</a>");
    zux_options_init(&o); o.max_depth=5;  run(deep,3,0,&o); total++;
    zux_options_init(&o); o.max_nodes=7;  run(deep,3,0,&o); total++;
    zux_options_init(&o); o.max_attrs=1;  run("<a x=\"1\" y=\"2\" z=\"3\"/>",1,0,&o); total++; }
  printf("driver completed %ld parses\n", total);
  return 0;
}
