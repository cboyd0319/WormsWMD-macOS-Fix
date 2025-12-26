/*
 * AGL Stub Library for macOS 26 (Tahoe) and later
 *
 * Apple removed the AGL (Apple OpenGL) framework in macOS 26.
 * This stub provides empty implementations of all AGL functions
 * to satisfy dynamic linking requirements for legacy applications.
 *
 * The functions return appropriate error values since modern
 * applications should use Core OpenGL (CGL) or Metal instead.
 *
 * NOTE: This stub is NOT thread-safe. The global agl_last_error state
 * could experience race conditions if called from multiple threads.
 * This is acceptable because the stub only returns errors anyway -
 * no actual AGL functionality is provided.
 */

#include <OpenGL/gl.h>
#include <stddef.h>

/* AGL Types */
typedef void* AGLPixelFormat;
typedef void* AGLContext;
typedef void* AGLDevice;
typedef void* AGLDrawable;
typedef void* AGLRendererInfo;
typedef void* AGLPbuffer;

/* AGL Error Codes */
#define AGL_NO_ERROR           0
#define AGL_BAD_ATTRIBUTE      10000
#define AGL_BAD_PROPERTY       10001
#define AGL_BAD_PIXELFMT       10002
#define AGL_BAD_RENDINFO       10003
#define AGL_BAD_CONTEXT        10004
#define AGL_BAD_DRAWABLE       10005
#define AGL_BAD_GDEV           10006
#define AGL_BAD_STATE          10007
#define AGL_BAD_VALUE          10008
#define AGL_BAD_MATCH          10009
#define AGL_BAD_ENUM           10010
#define AGL_BAD_OFFSCREEN      10011
#define AGL_BAD_FULLSCREEN     10012
#define AGL_BAD_WINDOW         10013
#define AGL_BAD_POINTER        10014
#define AGL_BAD_MODULE         10015
#define AGL_BAD_ALLOC          10016
#define AGL_BAD_CONNECTION     10017

/* Global error state */
static GLenum agl_last_error = AGL_NO_ERROR;

/* ========== Pixel Format Functions ========== */

AGLPixelFormat aglChoosePixelFormat(const void *gdevs, GLint ndev, const GLint *attribs) {
    (void)gdevs; (void)ndev; (void)attribs;
    agl_last_error = AGL_BAD_CONTEXT;
    return NULL;
}

void aglDestroyPixelFormat(AGLPixelFormat pix) {
    (void)pix;
}

AGLPixelFormat aglNextPixelFormat(AGLPixelFormat pix) {
    (void)pix;
    return NULL;
}

GLboolean aglDescribePixelFormat(AGLPixelFormat pix, GLint attrib, GLint *value) {
    (void)pix; (void)attrib; (void)value;
    agl_last_error = AGL_BAD_PIXELFMT;
    return GL_FALSE;
}

AGLDevice* aglDevicesOfPixelFormat(AGLPixelFormat pix, GLint *ndevs) {
    (void)pix;
    if (ndevs) *ndevs = 0;
    return NULL;
}

/* ========== Renderer Information Functions ========== */

AGLRendererInfo aglQueryRendererInfo(const AGLDevice *gdevs, GLint ndev) {
    (void)gdevs; (void)ndev;
    agl_last_error = AGL_BAD_CONTEXT;
    return NULL;
}

void aglDestroyRendererInfo(AGLRendererInfo rend) {
    (void)rend;
}

AGLRendererInfo aglNextRendererInfo(AGLRendererInfo rend) {
    (void)rend;
    return NULL;
}

GLboolean aglDescribeRenderer(AGLRendererInfo rend, GLint prop, GLint *value) {
    (void)rend; (void)prop; (void)value;
    agl_last_error = AGL_BAD_RENDINFO;
    return GL_FALSE;
}

/* ========== Context Functions ========== */

AGLContext aglCreateContext(AGLPixelFormat pix, AGLContext share) {
    (void)pix; (void)share;
    agl_last_error = AGL_BAD_CONTEXT;
    return NULL;
}

GLboolean aglDestroyContext(AGLContext ctx) {
    (void)ctx;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglCopyContext(AGLContext src, AGLContext dst, GLuint mask) {
    (void)src; (void)dst; (void)mask;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglUpdateContext(AGLContext ctx) {
    (void)ctx;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglSetCurrentContext(AGLContext ctx) {
    (void)ctx;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

AGLContext aglGetCurrentContext(void) {
    return NULL;
}

/* ========== Drawable Functions ========== */

GLboolean aglSetDrawable(AGLContext ctx, AGLDrawable draw) {
    (void)ctx; (void)draw;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglSetFullScreen(AGLContext ctx, GLint width, GLint height, GLint freq, GLint device) {
    (void)ctx; (void)width; (void)height; (void)freq; (void)device;
    agl_last_error = AGL_BAD_FULLSCREEN;
    return GL_FALSE;
}

AGLDrawable aglGetDrawable(AGLContext ctx) {
    (void)ctx;
    return NULL;
}

/* ========== Virtual Screen Functions ========== */

GLboolean aglSetVirtualScreen(AGLContext ctx, GLint screen) {
    (void)ctx; (void)screen;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLint aglGetVirtualScreen(AGLContext ctx) {
    (void)ctx;
    return 0;
}

/* ========== Offscreen Rendering Functions ========== */

GLboolean aglSetOffScreen(AGLContext ctx, GLint width, GLint height, GLint rowbytes, void *baseaddr) {
    (void)ctx; (void)width; (void)height; (void)rowbytes; (void)baseaddr;
    agl_last_error = AGL_BAD_OFFSCREEN;
    return GL_FALSE;
}

GLboolean aglGetOffScreen(AGLContext ctx, GLint *width, GLint *height, GLint *rowbytes, void **baseaddr) {
    (void)ctx; (void)width; (void)height; (void)rowbytes; (void)baseaddr;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

/* ========== Option Functions ========== */

GLboolean aglEnable(AGLContext ctx, GLenum pname) {
    (void)ctx; (void)pname;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglDisable(AGLContext ctx, GLenum pname) {
    (void)ctx; (void)pname;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglIsEnabled(AGLContext ctx, GLenum pname) {
    (void)ctx; (void)pname;
    return GL_FALSE;
}

GLboolean aglSetInteger(AGLContext ctx, GLenum pname, const GLint *params) {
    (void)ctx; (void)pname; (void)params;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglGetInteger(AGLContext ctx, GLenum pname, GLint *params) {
    (void)ctx; (void)pname; (void)params;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

/* ========== Font Functions ========== */

GLboolean aglUseFont(AGLContext ctx, GLint fontID, GLint face, GLint size, GLint first, GLint count, GLint base) {
    (void)ctx; (void)fontID; (void)face; (void)size; (void)first; (void)count; (void)base;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

/* ========== Error Functions ========== */

GLenum aglGetError(void) {
    GLenum err = agl_last_error;
    agl_last_error = AGL_NO_ERROR;
    return err;
}

const GLubyte* aglErrorString(GLenum code) {
    switch (code) {
        case AGL_NO_ERROR:       return (const GLubyte*)"No error";
        case AGL_BAD_ATTRIBUTE:  return (const GLubyte*)"Bad attribute";
        case AGL_BAD_PROPERTY:   return (const GLubyte*)"Bad property";
        case AGL_BAD_PIXELFMT:   return (const GLubyte*)"Bad pixel format";
        case AGL_BAD_RENDINFO:   return (const GLubyte*)"Bad renderer info";
        case AGL_BAD_CONTEXT:    return (const GLubyte*)"Bad context";
        case AGL_BAD_DRAWABLE:   return (const GLubyte*)"Bad drawable";
        case AGL_BAD_GDEV:       return (const GLubyte*)"Bad graphics device";
        case AGL_BAD_STATE:      return (const GLubyte*)"Bad state";
        case AGL_BAD_VALUE:      return (const GLubyte*)"Bad value";
        case AGL_BAD_MATCH:      return (const GLubyte*)"Bad match";
        case AGL_BAD_ENUM:       return (const GLubyte*)"Bad enum";
        case AGL_BAD_OFFSCREEN:  return (const GLubyte*)"Bad offscreen";
        case AGL_BAD_FULLSCREEN: return (const GLubyte*)"Bad fullscreen";
        case AGL_BAD_WINDOW:     return (const GLubyte*)"Bad window";
        case AGL_BAD_POINTER:    return (const GLubyte*)"Bad pointer";
        case AGL_BAD_MODULE:     return (const GLubyte*)"Bad module";
        case AGL_BAD_ALLOC:      return (const GLubyte*)"Bad alloc";
        case AGL_BAD_CONNECTION: return (const GLubyte*)"Bad connection";
        default:                 return (const GLubyte*)"Unknown error";
    }
}

/* ========== Buffer Management ========== */

void aglSwapBuffers(AGLContext ctx) {
    (void)ctx;
}

/* ========== Display Functions ========== */

GLboolean aglConfigure(GLenum pname, GLuint param) {
    (void)pname; (void)param;
    return GL_FALSE;
}

void aglResetLibrary(void) {
    agl_last_error = AGL_NO_ERROR;
}

/* ========== PBuffer Functions ========== */

GLboolean aglCreatePBuffer(GLint width, GLint height, GLenum target, GLenum internalFormat, long max_level, AGLPbuffer *pbuffer) {
    (void)width; (void)height; (void)target; (void)internalFormat; (void)max_level;
    if (pbuffer) *pbuffer = NULL;
    agl_last_error = AGL_BAD_ALLOC;
    return GL_FALSE;
}

GLboolean aglDestroyPBuffer(AGLPbuffer pbuffer) {
    (void)pbuffer;
    return GL_FALSE;
}

GLboolean aglDescribePBuffer(AGLPbuffer pbuffer, GLint *width, GLint *height, GLenum *target, GLenum *internalFormat, GLint *max_level) {
    (void)pbuffer; (void)width; (void)height; (void)target; (void)internalFormat; (void)max_level;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglTexImagePBuffer(AGLContext ctx, AGLPbuffer pbuffer, GLint source) {
    (void)ctx; (void)pbuffer; (void)source;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglSetPBuffer(AGLContext ctx, AGLPbuffer pbuffer, GLint face, GLint level, GLint screen) {
    (void)ctx; (void)pbuffer; (void)face; (void)level; (void)screen;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglGetPBuffer(AGLContext ctx, AGLPbuffer *pbuffer, GLint *face, GLint *level, GLint *screen) {
    (void)ctx; (void)pbuffer; (void)face; (void)level; (void)screen;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

/* ========== CGLContext Interop ========== */

GLboolean aglGetCGLContext(AGLContext ctx, void **cgl_ctx) {
    (void)ctx;
    if (cgl_ctx) *cgl_ctx = NULL;
    agl_last_error = AGL_BAD_CONTEXT;
    return GL_FALSE;
}

GLboolean aglGetCGLPixelFormat(AGLPixelFormat pix, void **cgl_pix) {
    (void)pix;
    if (cgl_pix) *cgl_pix = NULL;
    agl_last_error = AGL_BAD_PIXELFMT;
    return GL_FALSE;
}
