/* Exercise quantiser policy at the production macroblock boundary. */
#include <stdio.h>
#include <string.h>
#include "libavcodec/mpeg12dec.c"

static unsigned char bits[256 + AV_INPUT_BUFFER_PADDING_SIZE];
static int used;

static void put(const char *text)
{
    for (; *text; text++, used++)
        if (*text == '1')
            bits[used / 8] |= 1 << (7 - used % 8);
}

static void clear_blocks(int16_t *blocks)
{
    memset(blocks, 0, 6 * 64 * sizeof(*blocks));
}

int main(void)
{
    int total = 0, failed = 0;
    ff_mpeg12_init_vlcs();
    av_log_set_level(AV_LOG_QUIET);
    /* MPEG-1 linear, MPEG-2 linear/nonlinear, and the VCR2 shared decoder. */
    for (int policy = 0; policy < 4; policy++) {
        for (int strict = 0; strict < 2; strict++) {
            for (int branch = 0; branch < 3; branch++) {
                for (int code = 0; code <= 2; code += 2) {
                    Mpeg12SliceContext s = {0};
                    AVCodecContext context = {0};
                    uint32_t mb_type = 0;
                    s.c.avctx = &context;
                    context.err_recognition = strict ? AV_EF_EXPLODE : 0;
                    s.c.codec_id = policy == 0 ? AV_CODEC_ID_MPEG1VIDEO : AV_CODEC_ID_MPEG2VIDEO;
                    s.c.codec_tag = policy == 3 ? AV_RL32("VCR2") : 0;
                    s.c.q_scale_type = policy == 2;
                    s.c.pict_type = branch == 0 ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_P;
                    s.c.picture_structure = PICT_FRAME;
                    s.c.frame_pred_frame_dct = 1;
                    s.c.chroma_format = s.c.chroma_y_shift = 1;
                    s.c.qscale = 4;
                    s.c.bdsp.clear_blocks = clear_blocks;
                    s.c.cur_pic.mb_type = &mb_type;
                    s.c.mb_stride = 1;
                    s.last_dc[0] = s.last_dc[1] = s.last_dc[2] = 128;
                    for (int i = 0; i < 2; i++)
                        for (int k = 0; k < 2; k++)
                            s.c.mpeg_f_code[i][k] = 1;
                    for (int i = 0; i < 64; i++) {
                        s.c.intra_matrix[i] = s.c.chroma_intra_matrix[i] = 16;
                        s.c.inter_matrix[i] = s.c.chroma_inter_matrix[i] = 16;
                        s.c.intra_scantable.permutated[i] = i;
                        s.c.inter_scantable.permutated[i] = i;
                    }
                    s.c.intra_matrix[0] = s.c.chroma_intra_matrix[0] = 8;
                    memset(bits, 0, sizeof(bits));
                    used = 0;
                    put(branch == 0 ? "01" : branch == 1 ? "00001" : "00010");
                    put(code == 0 ? "00000" : "00010");
                    int update_end = used;
                    if (branch == 0) {
                        for (int i = 0; i < 6; i++)
                            put(i < 4 ? "10010" : "0010");
                    } else {
                        if (branch == 2)
                            put("11");
                        put("1010"); /* CBP 32. */
                        put("000001000000"); /* Escape, run 0, level 16. */
                        put(policy == 0 ? "00010000" : "000000010000");
                        put("10");
                    }
                    init_get_bits(&s.gb, bits, used);
                    int skip = 0;
                    int result = mpeg_decode_mb(&s, &skip);
                    int refuse = strict && policy != 3 && code == 0;
                    int ok = result == (refuse ? AVERROR_INVALIDDATA : 0) &&
                             get_bits_count(&s.gb) == (refuse ? update_end : used);
                    printf("%s policy=%d strict=%d branch=%d code=%d ret=%d bits=%d/%d\n",
                           ok ? "PASS" : "FAIL", policy, strict, branch, code,
                           result, get_bits_count(&s.gb), used);
                    total++;
                    failed += !ok;
                }
            }
        }
    }
    printf("cases=%d failed=%d\n", total, failed);
    return !!failed;
}
