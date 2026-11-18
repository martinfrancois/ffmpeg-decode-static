/* Direct macroblock tests: syntax is supplied at the production decoder boundary. */
#include <stdio.h>
#include <string.h>
#include "libavcodec/mpeg12dec.c"
static unsigned char bits[256 + AV_INPUT_BUFFER_PADDING_SIZE];
static int used;
static void put(const char *s) {
    for (; *s; s++,used++) if (*s=='1') bits[used/8] |= 1 << (7-used%8);
}
static unsigned hash_bytes(unsigned h, const void *data, size_t size) {
    const unsigned char *p=data;
    while(size--) h=(h ^ *p++) * 16777619U;
    return h;
}
static void clear_blocks(int16_t *b) { memset(b,0,6*64*sizeof(*b)); }
struct mode { const char *name; int structure, type, conceal, vectors; };
static const struct mode modes[] = {
    {"frame", PICT_FRAME, MT_FRAME, 0, 2},
    {"16x8", PICT_TOP_FIELD, MT_16X8, 0, 4},
    {"field-in-frame", PICT_FRAME, MT_FIELD, 0, 4},
    {"field-in-field", PICT_TOP_FIELD, MT_FIELD, 0, 2},
    {"dual-prime-frame", PICT_FRAME, MT_DMV, 0, 2},
    {"dual-prime-field", PICT_TOP_FIELD, MT_DMV, 0, 2},
    {"conceal-frame", PICT_FRAME, 0, 1, 2},
    {"conceal-field", PICT_TOP_FIELD, 0, 1, 2},
};
int main(void) {
    int failed=0,total=0;
    ff_mpeg12_init_vlcs();
    av_log_set_level(AV_LOG_QUIET);
    for (unsigned n=0;n<sizeof(modes)/sizeof(*modes);n++) {
      const struct mode *m=&modes[n];
      for (int bad=-1;bad<m->vectors;bad++) {
        Mpeg12SliceContext s={0}; AVCodecContext ctx={0}; uint32_t mb=0;
        s.c.avctx=&ctx; s.c.codec_id=AV_CODEC_ID_MPEG2VIDEO;
        s.c.pict_type=m->conceal?AV_PICTURE_TYPE_I:AV_PICTURE_TYPE_P;
        s.c.picture_structure=m->structure;
        s.c.frame_pred_frame_dct=m->structure==PICT_FRAME && (m->type==MT_FRAME || m->conceal);
        s.c.concealment_motion_vectors=m->conceal;
        s.c.chroma_format=1; s.c.chroma_y_shift=1; s.c.qscale=4;
        s.c.bdsp.clear_blocks=clear_blocks; s.c.cur_pic.mb_type=&mb;
        s.c.mb_stride=1;
        for(int i=0;i<2;i++) for(int k=0;k<2;k++) s.c.mpeg_f_code[i][k]=1;
        for(int i=0;i<64;i++) {s.c.intra_matrix[i]=16;s.c.chroma_intra_matrix[i]=16;s.c.intra_scantable.permutated[i]=i;}
        s.last_dc[0]=s.last_dc[1]=s.last_dc[2]=128;
        memset(bits,0,sizeof(bits)); used=0; int bad_at=-1;
        put(m->conceal?"1":"001");
        if (!m->conceal && !s.c.frame_pred_frame_dct) put(m->type==MT_DMV?"11":m->type==MT_FIELD?"01":"10");
        if(m->conceal && m->structure!=PICT_FRAME) put("0");
        for(int v=0;v<m->vectors;v++) {
          if(!m->conceal && m->type!=MT_DMV && !(m->structure==PICT_FRAME && m->type==MT_FRAME) && v%2==0) put("0");
          if(v==bad) {bad_at=used;put("00000000000000000000000000000000");break;}
          put("011"); /* magnitude one, negative sign: a legal vector of -1 */
          if(m->type==MT_DMV) put("0"); /* zero differential vector */
        }
        if(m->conceal && bad<0) {
          put("1"); /* marker */
          for(int i=0;i<6;i++) put(i<4?"10010":"0010");
        }
        init_get_bits(&s.gb,bits,used);
        int skip=0,ret=mpeg_decode_mb(&s,&skip);
        int ok=bad<0 ? ret==0 && s.c.mv[0][0][0]==-1 && get_bits_count(&s.gb)==used : ret==AVERROR_INVALIDDATA && get_bits_count(&s.gb)==bad_at;
        unsigned state=hash_bytes(hash_bytes(hash_bytes(2166136261U,s.c.mv,sizeof(s.c.mv)),s.c.last_mv,sizeof(s.c.last_mv)),s.block,sizeof(s.block));
        printf("%s mode=%s bad_component=%d ret=%d horizontal=%d bits=%d/%d state=%08x\n",ok?"PASS":"FAIL",m->name,bad,ret,s.c.mv[0][0][0],get_bits_count(&s.gb),used,state);
        failed+=!ok;total++;
      }
    }
    struct helper_case { const char *bits; int fcode, pred, expected; } helper[] = {
      {"1",1,-7,-7}, {"011",1,0,-1}, {"010",1,0,1},
      {"01111",3,0,-4}, {"011",1,-16,15}, {"010",1,15,-16},
      {"00000000000000000000000000000000",1,0,1234}
    };
    for(unsigned i=0;i<sizeof(helper)/sizeof(*helper);i++) {
      Mpeg12SliceContext s={0}; int output=1234,ret=0;
      memset(bits,0,sizeof(bits));used=0;put(helper[i].bits);
      init_get_bits(&s.gb,bits,used);
      ret=mpeg_decode_motion(&s,helper[i].fcode,helper[i].pred,&output);
      int invalid=i==6;
      int ok=ret==(invalid?AVERROR_INVALIDDATA:0) && output==helper[i].expected;
      printf("%s helper=%u ret=%d vector=%d expected=%d\n",ok?"PASS":"FAIL",i,ret,output,helper[i].expected);
      total++;failed+=!ok;
    }
    printf("cases=%d failed=%d\n",total,failed);
    return !!failed;
}
