## Audio DAC - Electronic Music DAW
## Build system for Chicken Scheme + C DSP engine + Nuklear GUI

CSC      = csc
CC       = gcc
CFLAGS   = -O2 -Wall -Wextra -I./csrc -I./lib/nuklear $(shell pkg-config --cflags sdl2)
LDFLAGS  = $(shell pkg-config --libs sdl2) -lm -ldl

C_DEPS   = csrc/ringbuffer.c csrc/ringbuffer.h \
           csrc/dsp-core.c csrc/dsp-core.h \
           csrc/audio-backend.c csrc/audio-backend.h \
           csrc/sample-engine.c csrc/sample-engine.h \
           csrc/effects.c csrc/effects.h \
           csrc/gui-backend.c csrc/gui-backend.h \
           lib/nuklear/nuklear.h lib/nuklear/nuklear_sdl_renderer.h

.PHONY: all clean run run-headless

all: audio-dac

audio-dac: audio-dac.scm $(C_DEPS)
	$(CSC) -O2 audio-dac.scm \
		-C "-I./csrc -I./lib/nuklear $(shell pkg-config --cflags sdl2)" \
		-L "$(shell pkg-config --libs sdl2)" \
		-L "-lm -ldl" \
		-o audio-dac

run: audio-dac
	./audio-dac

run-headless: audio-dac
	./audio-dac --no-gui

clean:
	rm -f audio-dac audio-dac.c csrc/*.o
