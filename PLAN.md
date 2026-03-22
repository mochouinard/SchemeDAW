# Audio DAC: Electronic Music DAW in Chicken Scheme

## Context
Building a full-featured electronic music DAW from scratch using Chicken Scheme. The DAW targets Linux, uses Nuklear+SDL2 for GUI, SDL2 for audio, and will host VST3 plugins. Core features: built-in synthesizers, step sequencer, sample playback, and live coding via REPL.

## Architecture: C for Real-Time, Scheme for Composition

The critical design decision: **C handles everything inside the audio callback** (SDL2 audio runs on a separate OS thread; Chicken Scheme's runtime isn't thread-safe across OS threads). **Scheme handles everything else** (GUI, sequencing logic, live coding, plugin management). Communication uses a **lock-free SPSC ring buffer**.

## Project Structure

```
audio-dac/
├── Makefile
├── audio-dac.scm                 # Main entry point
├── lib/
│   ├── nuklear/                  # Vendored Nuklear headers
│   └── vst3/                     # VST3 C API header
├── csrc/                         # C code (real-time safe)
│   ├── ringbuffer.c/h            # Lock-free SPSC ring buffer
│   ├── dsp-core.c/h              # Oscillators, filters, envelopes, voice pool
│   ├── audio-backend.c/h         # SDL2 audio init + callback
│   ├── sample-engine.c/h         # WAV loading + sample playback
│   ├── gui-backend.c/h           # Nuklear+SDL2 init + high-level widgets
│   └── vst3-host.c/h             # VST3 plugin loading via C API
├── src/                          # Scheme modules
│   ├── engine/
│   │   ├── audio.scm             # FFI to audio-backend.c
│   │   ├── dsp.scm               # FFI to dsp-core.c
│   │   ├── mixer.scm             # Track/bus topology
│   │   ├── clock.scm             # Transport: BPM, tick timing
│   │   └── sampler.scm           # FFI to sample-engine.c
│   ├── synth/
│   │   ├── oscillator.scm        # Osc constructors
│   │   ├── filter.scm            # Filter wrappers
│   │   ├── envelope.scm          # ADSR envelopes
│   │   ├── modulation.scm        # LFOs, mod matrix
│   │   ├── subtractive.scm       # Subtractive synth template
│   │   ├── fm.scm                # FM synth template
│   │   └── wavetable.scm         # Wavetable synth template
│   ├── sequencer/
│   │   ├── pattern.scm           # Pattern data structure
│   │   ├── sequencer.scm         # Step sequencer engine
│   │   ├── arrangement.scm       # Song arrangement
│   │   └── midi.scm              # MIDI note/CC output
│   ├── fx/
│   │   ├── delay.scm
│   │   ├── reverb.scm
│   │   ├── distortion.scm
│   │   └── fx-chain.scm
│   ├── vst3/
│   │   └── host.scm              # VST3 plugin management
│   ├── gui/
│   │   ├── backend.scm           # FFI to gui-backend.c
│   │   ├── main-window.scm       # Top-level layout
│   │   ├── synth-panel.scm       # Synth editor
│   │   ├── sequencer-panel.scm   # Step grid
│   │   ├── mixer-panel.scm       # Mixer faders/meters
│   │   ├── sample-panel.scm      # Sample browser
│   │   └── widgets.scm           # Reusable DAW widgets
│   └── live/
│       ├── repl.scm              # NREPL on TCP port 7770
│       └── api.scm               # User-facing live-coding API
├── presets/                      # Bundled synth presets (.scm)
├── samples/                      # Bundled WAV samples
└── tests/
```

## Audio Engine Signal Flow

```
[Scheme Thread] --ring buffer--> [C Audio Callback (SDL thread)]
                                       |
                   +-------------------+-------------------+
                   v                   v                   v
             Voice Pool          Voice Pool          Sample Player
             (Synth tracks)      (FM tracks)         (drum tracks)
                   |                   |                   |
                   v                   v                   v
             FX Chain            FX Chain            FX Chain
                   |                   |                   |
                   +--------+----------+--------+----------+
                            v                   v
                        Bus (Synths)        Bus (Drums)
                            +--------+----------+
                                     v
                               Master Bus --> SDL Audio Out
```

## Key C Data Structures

- **Voice pool**: MAX_VOICES=64 pre-allocated voices with 3 oscillators, filter, 2 envelopes each
- **Track**: MAX_TRACKS=16, each with voice pool reference, FX chain (8 slots), volume/pan/mute/solo
- **Ring buffer**: 4096 fixed-size commands (type, track, param1, param2, float value)
- **Sample slots**: MAX_SAMPLES=256 pre-loaded WAV buffers, 32 sample playback voices

## Implementation Phases

### Phase 1: Foundation
1. Project skeleton + Makefile
2. `csrc/ringbuffer.c` - lock-free SPSC ring buffer
3. `csrc/dsp-core.c` - sine oscillator + simple filter
4. `csrc/audio-backend.c` - SDL2 audio device, callback, command processing
5. `src/engine/audio.scm` - FFI bindings
6. **Milestone: Play a sine wave from the REPL**

### Phase 2: Synthesizers
1. All oscillator waveforms (saw, square, triangle, wavetable)
2. State-variable filter (LP/HP/BP)
3. ADSR envelopes
4. Voice allocation + stealing
5. Scheme synth definition layer
6. FM synthesis mode
7. **Milestone: Play subtractive/FM synths with note-on/off**

### Phase 3: Sequencer + Clock
1. Clock/transport in Scheme (96 PPQN, drift compensation)
2. Pattern data structures
3. Step sequencer engine
4. Wire clock -> pattern -> ring buffer
5. **Milestone: Patterns playing in tempo**

### Phase 4: Sample Engine
1. WAV loading in C (via SDL_LoadWAV)
2. Sample playback voices
3. Scheme bindings
4. Drum machine mode in sequencer
5. **Milestone: Load and trigger WAV files from patterns**

### Phase 5: Effects
1. Delay, reverb (Schroeder), distortion in C
2. Per-track effect chain management
3. **Milestone: FX chains working**

### Phase 6: GUI
1. `csrc/gui-backend.c` - Nuklear+SDL2 init + high-level widget C functions
2. Scheme FFI for GUI
3. Sequencer grid, synth editor, mixer, toolbar panels
4. **Milestone: Full interactive GUI**

### Phase 7: Live Coding
1. NREPL integration (TCP port 7770)
2. Live API: `play!`, `stop!`, `bpm!`, `note!`, `pat!`, `synth!`, `sample!`, `fx!`
3. Pattern shorthand parser
4. **Milestone: Live coding workflow functional**

### Phase 8: VST3 Hosting
1. `csrc/vst3-host.c` using VST3 C API (dlopen, vtable calls)
2. Plugin scanning, parameter enumeration
3. Audio processing integration into track pipeline
4. Scheme bindings
5. **Milestone: Load and play VST3 plugins**

## GUI Layout

```
+------------------------------------------------------------------+
| [File] [Edit] [View]    BPM: [120]  [Play] [Stop] [Rec]         |
+------------------------------------------------------------------+
|                        |                                          |
|   SEQUENCER GRID       |         SYNTH EDITOR                    |
|   (tracker-style)      |   [Subtractive] [FM] [Wavetable]        |
|   rows=steps           |   Oscillators, Filter, Envelopes        |
|   cols=tracks          |   knobs + sliders                        |
|                        |                                          |
+------------------------+------------------------------------------+
|   MIXER - per-track faders, solo/mute, VU meters, master         |
+------------------------------------------------------------------+
```

## Key Technical Risks

1. **Audio callback timing**: Mitigated by all DSP in pure C, ring buffer only comm path
2. **Sequencer jitter**: Drift-compensated sleep; fallback to sample-accurate C-side ticking
3. **VST3 complexity**: Deferred to Phase 8; CLAP as fallback alternative
4. **Nuklear FFI surface**: High-level C widget functions (knob, fader, grid, meter) not raw Nuklear
5. **GC pauses**: Audio callback unaffected (pure C); Scheme thread ops are lightweight

## Verification

After each phase milestone:
- Phase 1: Run binary, hear sine wave output
- Phase 2: REPL commands produce different synth sounds
- Phase 3: Programmatic pattern loops at correct BPM
- Phase 4: WAV files load and trigger on beat
- Phase 5: Audible delay/reverb/distortion on tracks
- Phase 6: GUI controls modify audio in real-time
- Phase 7: Connect via TCP REPL, live-modify running patterns
- Phase 8: Scan and load a known VST3 plugin
