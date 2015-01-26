ctypedef unsigned char[16] MD5_checksum

cdef extern from "md5.h":
    ctypedef unsigned int MD5_u32plus

    ctypedef struct MD5_CTX:
        MD5_u32plus lo, hi
        MD5_u32plus a, b, c, d
        unsigned char buffer[64]
        MD5_u32plus block[16]

    void MD5_Init(MD5_CTX *ctx)
    void MD5_Update(MD5_CTX *ctx, const void *data, unsigned long size)
    void MD5_Final(MD5_checksum result, MD5_CTX *ctx)
    unsigned char MD5_isClear(MD5_checksum result)
