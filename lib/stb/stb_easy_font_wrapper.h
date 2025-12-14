#pragma once

#include "stb_easy_font.h"
#include "stb_image_write.h"

// Expose a non-static version of stb_easy_font_print to make linking easier.
int stb_easy_font_print_wrapper(float x, float y, char *text, unsigned char color[4], void *vertex_buffer, int vbuf_size);
