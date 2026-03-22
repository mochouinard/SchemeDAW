use crate::dsp::oscillator::Waveform;
use crate::dsp::filter::FilterType;
use crate::audio::voice::{Voice, MAX_VOICES};

pub const MAX_TRACKS: usize = 16;

/// Track holds synth parameters and voice pool
pub struct Track {
    pub voices: Vec<Voice>,
    pub volume: f32,
    pub pan: f32,
    pub mute: bool,
    pub solo: bool,
    pub synth_type: u8,      // 0=subtractive, 1=fm

    // Oscillator defaults
    pub waveform: Waveform,
    pub osc_count: u8,
    pub osc2_wave: Waveform,
    pub osc3_wave: Waveform,
    pub osc2_detune: f32,
    pub osc3_detune: f32,
    pub osc2_mix: f32,
    pub osc3_mix: f32,
    pub osc2_octave: f32,
    pub osc3_octave: f32,

    // Filter
    pub cutoff: f32,
    pub resonance: f32,
    pub filter_type: FilterType,

    // Amp envelope
    pub amp_a: f32,
    pub amp_d: f32,
    pub amp_s: f32,
    pub amp_r: f32,

    // Filter envelope
    pub filt_a: f32,
    pub filt_d: f32,
    pub filt_s: f32,
    pub filt_r: f32,
    pub filt_env_amount: f32,

    // FM
    pub fm_ratio: f32,
    pub fm_index: f32,

    // Pitch envelope
    pub pitch_env_amount: f32,
    pub pitch_env_decay: f32,
}

impl Track {
    pub fn new(sample_rate: f32) -> Self {
        let mut voices = Vec::with_capacity(MAX_VOICES);
        for _ in 0..MAX_VOICES {
            voices.push(Voice::new(sample_rate));
        }

        Self {
            voices,
            volume: 0.8,
            pan: 0.0,
            mute: false,
            solo: false,
            synth_type: 0,
            waveform: Waveform::Saw,
            osc_count: 1,
            osc2_wave: Waveform::Saw,
            osc3_wave: Waveform::Sine,
            osc2_detune: 0.0,
            osc3_detune: 0.0,
            osc2_mix: 0.8,
            osc3_mix: 0.5,
            osc2_octave: 0.0,
            osc3_octave: 0.0,
            cutoff: 4000.0,
            resonance: 0.3,
            filter_type: FilterType::LowPass,
            amp_a: 0.01, amp_d: 0.2, amp_s: 0.7, amp_r: 0.3,
            filt_a: 0.01, filt_d: 0.3, filt_s: 0.3, filt_r: 0.5,
            filt_env_amount: 2000.0,
            fm_ratio: 2.0,
            fm_index: 0.0,
            pitch_env_amount: 0.0,
            pitch_env_decay: 0.1,
        }
    }

    pub fn note_on(&mut self, note: u8, velocity: u8, sample_rate: f32, voice_counter: &mut u32) {
        if velocity == 0 {
            self.note_off(note);
            return;
        }

        let vel_f = velocity as f32 / 127.0;
        let age = *voice_counter;
        *voice_counter += 1;

        // Find free voice or steal oldest
        let idx = self.voices.iter().position(|v| !v.active)
            .unwrap_or_else(|| {
                self.voices.iter().enumerate()
                    .min_by_key(|(_, v)| v.age)
                    .map(|(i, _)| i)
                    .unwrap_or(0)
            });

        // Clean stolen voice
        if self.voices[idx].active {
            self.voices[idx].amp_env.level = 0.0;
            self.voices[idx].active = false;
        }

        // Extract params to avoid borrow conflict
        let params = TrackParams {
            synth_type: self.synth_type,
            waveform: self.waveform, osc_count: self.osc_count,
            osc2_wave: self.osc2_wave, osc3_wave: self.osc3_wave,
            osc2_detune: self.osc2_detune, osc3_detune: self.osc3_detune,
            osc2_mix: self.osc2_mix, osc3_mix: self.osc3_mix,
            osc2_octave: self.osc2_octave, osc3_octave: self.osc3_octave,
            cutoff: self.cutoff, resonance: self.resonance, filter_type: self.filter_type,
            amp_a: self.amp_a, amp_d: self.amp_d, amp_s: self.amp_s, amp_r: self.amp_r,
            filt_a: self.filt_a, filt_d: self.filt_d, filt_s: self.filt_s, filt_r: self.filt_r,
            filt_env_amount: self.filt_env_amount,
            fm_ratio: self.fm_ratio, fm_index: self.fm_index,
            pitch_env_amount: self.pitch_env_amount, pitch_env_decay: self.pitch_env_decay,
        };
        self.voices[idx].note_on_with_params(note, vel_f, sample_rate, &params, age);
    }

    pub fn note_off(&mut self, note: u8) {
        for v in &mut self.voices {
            if v.active && v.note == note {
                v.note_off();
            }
        }
    }

    pub fn all_notes_off(&mut self) {
        for v in &mut self.voices {
            if v.active { v.note_off(); }
        }
    }

    pub fn render(&mut self, left: &mut [f32], right: &mut [f32], sample_rate: f32) {
        // Zero buffers
        for s in left.iter_mut() { *s = 0.0; }
        for s in right.iter_mut() { *s = 0.0; }

        // Copy track params for voice rendering (avoids borrow conflict)
        let track_snapshot = TrackParams {
            synth_type: self.synth_type,
            waveform: self.waveform,
            osc_count: self.osc_count,
            osc2_wave: self.osc2_wave, osc3_wave: self.osc3_wave,
            osc2_detune: self.osc2_detune, osc3_detune: self.osc3_detune,
            osc2_mix: self.osc2_mix, osc3_mix: self.osc3_mix,
            osc2_octave: self.osc2_octave, osc3_octave: self.osc3_octave,
            cutoff: self.cutoff, resonance: self.resonance, filter_type: self.filter_type,
            amp_a: self.amp_a, amp_d: self.amp_d, amp_s: self.amp_s, amp_r: self.amp_r,
            filt_a: self.filt_a, filt_d: self.filt_d, filt_s: self.filt_s, filt_r: self.filt_r,
            filt_env_amount: self.filt_env_amount,
            fm_ratio: self.fm_ratio, fm_index: self.fm_index,
            pitch_env_amount: self.pitch_env_amount, pitch_env_decay: self.pitch_env_decay,
        };

        // Render each active voice
        for v in &mut self.voices {
            if v.active {
                v.render_with_params(left, right, sample_rate, &track_snapshot);
            }
        }

        // Apply track volume and pan
        let pan_r = (self.pan + 1.0) * 0.5;
        let pan_l = 1.0 - pan_r;
        for i in 0..left.len() {
            left[i] *= self.volume * pan_l;
            right[i] *= self.volume * pan_r;
        }
    }
}

/// Snapshot of track params for voice rendering (avoids borrow issues)
pub struct TrackParams {
    pub synth_type: u8,
    pub waveform: Waveform,
    pub osc_count: u8,
    pub osc2_wave: Waveform, pub osc3_wave: Waveform,
    pub osc2_detune: f32, pub osc3_detune: f32,
    pub osc2_mix: f32, pub osc3_mix: f32,
    pub osc2_octave: f32, pub osc3_octave: f32,
    pub cutoff: f32, pub resonance: f32, pub filter_type: FilterType,
    pub amp_a: f32, pub amp_d: f32, pub amp_s: f32, pub amp_r: f32,
    pub filt_a: f32, pub filt_d: f32, pub filt_s: f32, pub filt_r: f32,
    pub filt_env_amount: f32,
    pub fm_ratio: f32, pub fm_index: f32,
    pub pitch_env_amount: f32, pub pitch_env_decay: f32,
}
