## Audio DAC - Electronic Music DAW
## Build system for Chicken Scheme + C DSP engine

CSC      = csc
CC       = gcc
CFLAGS   = -O2 -Wall -Wextra -I./csrc $(shell pkg-config --cflags sdl2)
LDFLAGS  = $(shell pkg-config --libs sdl2) -lm -ldl

# Phase 1: Single-file compilation (includes .c files directly via foreign-declare)
# Later phases will compile C separately and link .o files.

.PHONY: all clean run

all: audio-dac

audio-dac: audio-dac.scm csrc/ringbuffer.c csrc/ringbuffer.h \
           csrc/dsp-core.c csrc/dsp-core.h \
           csrc/audio-backend.c csrc/audio-backend.h
	$(CSC) -O2 audio-dac.scm \
		-C "-I./csrc $(shell pkg-config --cflags sdl2)" \
		-L "$(shell pkg-config --libs sdl2)" \
		-L "-lm" \
		-o audio-dac

run: audio-dac
	./audio-dac

clean:
	rm -f audio-dac audio-dac.c csrc/*.o

# ---- Future phases: separate compilation ----
# C_SOURCES = csrc/ringbuffer.c csrc/dsp-core.c csrc/audio-backend.c
# C_OBJECTS = $(C_SOURCES:.c=.o)
#
# csrc/%.o: csrc/%.c csrc/%.h
# 	$(CC) $(CFLAGS) -c $< -o $@
