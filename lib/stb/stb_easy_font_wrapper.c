// For some reason, using @cDefine for this in an @cImport block gives us linker errors.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_easy_font_wrapper.h"

int stb_easy_font_print_wrapper(float x, float y, char* text, unsigned char color[4], void* vertex_buffer, int vbuf_size) {
	return stb_easy_font_print(x, y, text, color, vertex_buffer, vbuf_size);
}
