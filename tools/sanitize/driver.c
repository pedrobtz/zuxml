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

static void tree_run(const char*doc,zux_options*o){
  zux_document*d=NULL; zux_error e; zux_id st[256]; size_t sp=0;
  if(zux_tree_parse(&d,doc,strlen(doc),o,&e)!=ZUX_OK||d==NULL) return;
  /* iterative walk, touching every accessor */
  st[sp++]=0;
  while(sp>0){
    zux_id id=st[--sp], c; uint32_t i,na;
    (void)zux_node_kind(d,id); (void)zux_parent(d,id);
    (void)zux_node_name(d,id); (void)zux_node_text(d,id);
    na=zux_attr_count(d,id);
    for(i=0;i<na;i++) (void)zux_attr_at(d,id,i);
    for(c=zux_first_child(d,id);c!=ZUX_NONE;c=zux_next_sibling(d,c))
      if(sp<256) st[sp++]=c;
  }
  (void)zux_root(d); (void)zux_doc_version(d); (void)zux_doc_encoding(d);
  /* serialize, then re-parse the output and serialize again: the round trip
   * is the property the test suite asserts, exercised here under ASan. */
  { char*out=NULL; size_t len=0;
    if(zux_serialize(d,0,&out,&len)==ZUX_OK && out!=NULL){
      zux_document*d2=NULL; zux_error e2;
      if(zux_tree_parse(&d2,out,len,o,&e2)==ZUX_OK && d2!=NULL){
        char*out2=NULL; size_t l2=0;
        if(zux_serialize(d2,0,&out2,&l2)==ZUX_OK) free(out2);
        zux_document_free(d2);
      }
      free(out);
    } }
  zux_document_free(d);
}

/* Build, walk and free a very deep document. Run under a small stack by
 * tools/run-sanitizers to prove construction, traversal and teardown are all
 * iterative -- a recursive implementation would crash here. */
static int deep_mode(void){
  size_t n=100000,i; zux_options o; zux_document*d=NULL; zux_error e;
  char*doc=malloc(n*7+16); char*p=doc;
  for(i=0;i<n;i++){memcpy(p,"<a>",3);p+=3;}
  for(i=0;i<n;i++){memcpy(p,"</a>",4);p+=4;}
  *p=0;
  zux_options_init(&o); o.max_depth=(uint32_t)n+10; o.max_memory=(size_t)512*1024*1024;
  if(zux_tree_parse(&d,doc,strlen(doc),&o,&e)!=ZUX_OK||d==NULL){
    printf("deep: parse failed (%s)\n", zux_status_string(e.status)); free(doc); return 1;}
  printf("deep: built %u nodes, %u names\n", zux_node_count(d), zux_name_count(d));
  { zux_id id=zux_root(d); size_t walked=0;
    while(id!=ZUX_NONE){ walked++; id=zux_first_child(d,id); }
    printf("deep: walked %zu levels iteratively\n", walked); }
  { char*out=NULL; size_t len=0;
    if(zux_serialize(d,0,&out,&len)==ZUX_OK && out!=NULL){
      printf("deep: serialized %zu bytes iteratively\n", len); free(out);
    } else printf("deep: serialize FAILED\n"); }
  zux_document_free(d);
  free(doc);
  printf("deep: freed without recursion\n");
  return 0;
}

int main(int argc,char**argv){
  if(argc>1 && strcmp(argv[1],"deep")==0) return deep_mode();
  {
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
  /* same fixtures again, this time building trees */
  for(i=0;i<nd;i++){
    zux_options_init(&o); tree_run(docs[i],&o); total++;
    zux_options_init(&o); o.allow_doctype=1; tree_run(docs[i],&o); total++;
    zux_options_init(&o); o.keep_comments=0; o.keep_pis=0; tree_run(docs[i],&o); total++;
    zux_options_init(&o); o.max_memory=128; tree_run(docs[i],&o); total++;
    zux_options_init(&o); o.max_nodes=2; tree_run(docs[i],&o); total++;
  }
  printf("driver completed %ld parses\n", total);
  return 0;
  }
}
