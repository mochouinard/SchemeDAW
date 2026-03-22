# Audio DAC - Electronic Music DAW

A digital audio workstation for electronic music built with Chicken Scheme and a C real-time DSP engine. Features a Nuklear+SDL2 graphical interface, built-in synthesizers, step sequencer, sample playback, effects, live coding REPL, and VST3 plugin hosting.

## Requirements

### System Dependencies

**Debian/Ubuntu:**
```bash
sudo apt-get install chicken-bin libchicken-dev libsdl2-dev pkg-config gcc make
```

**Arch Linux:**
```bash
sudo pacman -S chicken sdl2 pkg-config gcc make
```

**Fedora:**
```bash
sudo dnf install chicken sdl2-devel pkg-config gcc make
```

### Verify Installation

```bash
csc -version        # Chicken Scheme compiler
pkg-config --cflags sdl2  # SDL2 development headers
gcc --version       # C compiler
```

## Building

```bash
make
```

This compiles the Scheme and C sources into a single binary (`audio-dac`, ~164KB).

To clean build artifacts:
```bash
make clean
```

## Running

### GUI Mode (default)

```bash
./audio-dac
```

Opens a 1280x800 window with:
- **Transport bar** — BPM control, Play/Stop button, step counter
- **Sequencer grid** — 8 tracks x 16 steps, click cells to toggle notes
- **Synth editor** — waveform selector (SIN/SAW/SQR/TRI/NSE), filter cutoff & resonance sliders
- **Mixer** — per-track volume sliders, Mute (M) and Solo (S) buttons

### Headless Mode

```bash
./audio-dac --no-gui
```

Plays a C minor arpeggio through the audio engine without opening a window. Useful for testing audio output.

### Using the Makefile

```bash
make run           # Build and run in GUI mode
make run-headless  # Build and run in headless mode
```

## GUI Controls

### Transport
- **BPM** — Click and drag the BPM value, or click and type a number (40-300)
- **PLAY/STOP** — Starts/stops the step sequencer

### Sequencer Grid
- Rows represent tracks (0-3: melodic notes C4/E4/G4/C5, 4-7: drums kick/snare/closed-HH/open-HH)
- Columns represent steps (1-16)
- Click a cell to toggle it on/off
- Active cells light up blue; the current playback position highlights yellow

### Synth Editor
- **Waveform buttons** — Select the oscillator waveform for track 0. The active waveform shows in brackets (e.g., `[SAW]`)
- **Cutoff slider** — Filter cutoff frequency (20-20000 Hz)
- **Resonance slider** — Filter resonance (0.0-0.99)

### Mixer
- **Volume sliders** — Per-track volume (0.0-1.0)
- **M button** — Mute/unmute a track
- **S button** — Solo/unsolo a track (only soloed tracks are heard)

## Live Coding

The DAW includes a live coding API designed for real-time performance via a TCP REPL. Connect with:

```bash
rlwrap nc localhost 7770
```

### Available Commands

```scheme
;; Transport
(play!)                    ; Start playback
(stop!)                    ; Stop and silence all
(bpm! 140)                 ; Set tempo

;; Notes (MIDI number or symbol)
(note! 0 60 100)           ; Track 0, C4, velocity 100
(note! 0 'C4 100)          ; Same thing
(note-off! 0 60)           ; Release note
(silence!)                 ; All notes off, all tracks
(silence! 0)               ; All notes off, track 0

;; Synth control
(wave! 0 'saw)             ; Set waveform (sine saw square tri noise)
(cutoff! 0 2000)           ; Filter cutoff in Hz
(reso! 0 0.6)              ; Filter resonance
(env! 0 0.01 0.2 0.7 0.3) ; ADSR envelope (attack decay sustain release)

;; Mixer
(vol! 0 0.8)               ; Track volume (0.0-1.0)
(pan! 0 -0.5)              ; Pan left (-1.0 to 1.0)
(mute! 0)                  ; Toggle mute
(solo! 0)                  ; Toggle solo

;; Pattern shorthand
(pat! '(C4 . C4 . E4 . G4 .))  ; Notes and rests (. = rest)
```

## Architecture

```
[Scheme Thread]                    [C Audio Thread (SDL2)]
  GUI, Sequencer,         --->       Audio Callback
  Live Coding, Patterns   ring       Oscillators, Filters,
                          buffer     Envelopes, Effects,
                                     Sample Playback
                                         |
                                    [SDL2 Audio Out]
```

- **C layer** (`csrc/`) — All real-time DSP. No allocations, no locks, no Scheme calls in the audio callback.
- **Scheme layer** (`src/`) — Composition, sequencing, GUI, live coding, plugin management.
- **Ring buffer** — Lock-free SPSC (Single-Producer Single-Consumer) queue bridges the two threads.

### Key Limits

| Resource         | Limit |
|-----------------|-------|
| Tracks          | 16    |
| Voices per track| 64    |
| Oscillators per voice | 3 |
| Effects per track | 8   |
| Sample slots    | 256   |
| Sample voices   | 32    |
| VST3 plugin slots | 16 |
| Ring buffer     | 4096 commands |

## Project Structure

```
audio-dac/
├── audio-dac.scm          # Main entry point (GUI + headless modes)
├── Makefile
├── csrc/                   # C real-time DSP code
│   ├── ringbuffer.c/h      # Lock-free SPSC ring buffer
│   ├── dsp-core.c/h        # Oscillators, filters, envelopes, voices
│   ├── audio-backend.c/h   # SDL2 audio device + callback
│   ├── sample-engine.c/h   # WAV loading + sample playback
│   ├── effects.c/h         # Delay, reverb, distortion, FX chains
│   ├── gui-backend.c/h     # Nuklear+SDL2 widgets
│   └── vst3-host.c/h       # VST3 plugin loading
├── src/                    # Scheme modules
│   ├── engine/             # Audio engine FFI, clock, mixer, sampler
│   ├── synth/              # Oscillator, filter, envelope, FM, wavetable
│   ├── sequencer/          # Patterns, step sequencer, arrangement, MIDI
│   ├── fx/                 # Effect parameter wrappers
│   ├── gui/                # GUI panels and widgets
│   ├── live/               # REPL server and live coding API
│   └── vst3/               # VST3 host FFI bindings
├── lib/nuklear/            # Vendored Nuklear GUI library
├── presets/                # Synth preset files (.scm)
└── samples/drums/          # Sample WAV files (add your own)
```

## Presets

Bundled synth presets in `presets/`:

- **bass-acid.scm** — Resonant saw with short decay, heavy filter envelope (303-style)
- **pad-warm.scm** — Slow attack saw with gentle filter sweep
- **kick-808.scm** — Sine wave with fast pitch decay (TR-808 style kick)

## Adding Samples

Place WAV files in `samples/drums/` or any directory. Load them via the live coding API (sample loading integration with the GUI is planned).

## VST3 Plugins

The VST3 host scans these directories for `.vst3` bundles:
- `/usr/lib/vst3`
- `/usr/local/lib/vst3`
- `~/.vst3`

The plugin loading infrastructure (dlopen, GetPluginFactory) is functional. Full VST3 COM interface integration for audio processing and parameter control requires the [VST3 C API header](https://github.com/steinbergmedia/vst3_c_api) from Steinberg.

## License

GPL-3.0
