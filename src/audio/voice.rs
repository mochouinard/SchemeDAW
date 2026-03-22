use crate::dsp::oscillator::{Oscillator, Waveform};
use crate::dsp::filter::Filter;
use crate::dsp::envelope::Envelope;
use crate::dsp::midi_to_freq;
use crate::audio::track::{Track, TrackParams};
use std::f32::consts::PI;

const TWO_PI: f32 = 2.0 * PI;
pub const MAX_VOICES: usize = 64;

#[derive(Clone)]
pub struct Voice {
    pub osc: [Oscillator; 3],
    pub osc_count: u8,
    pub filter: Filter,
    pub amp_env: Envelope,
    pub filter_env: Envelope,
    pub filter_env_amount: f32,
    pub velocity: f32,
    pub pan: f32,
    pub active: bool,
    pub note: u8,
    pub age: u32,
    // Per-voice pitch envelope
    pub pitch_env_level: f32,
    pub pitch_env_rate: f32,
    pub pitch_env_amount: f32,
    // FM modulator phase (per-voice, not shared!)
    pub fm_mod_phase: f32,
    // Anti-click fade-in
    pub fade_in: f32,
    pub fade_in_samples: i32,
}

impl Voice {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            osc: std::array::from_fn(|_| Oscillator::new()),
            osc_count: 1,
            filter: Filter::new(),
            amp_env: Envelope::new(sample_rate),
            filter_env: Envelope::new(sample_rate),
            filter_env_amount: 0.0,
            velocity: 1.0,
            pan: 0.0,
            active: false,
            note: 0,
            age: 0,
            pitch_env_level: 0.0,
            pitch_env_rate: 0.0,
            pitch_env_amount: 0.0,
            fm_mod_phase: 0.0,
            fade_in: 1.0,
            fade_in_samples: 1,
        }
    }

    pub fn note_on_with_params(&mut self, note: u8, velocity: f32, sample_rate: f32, track: &TrackParams, age: u32) {
        self.active = true;
        self.note = note;
        self.velocity = velocity;
        self.age = age;

        let freq = midi_to_freq(note);

        // Set up oscillators
        self.osc_count = track.osc_count.clamp(1, 3);
        self.osc[0].init(track.waveform, freq, sample_rate);
        self.osc[0].mix_level = 1.0;

        if self.osc_count >= 2 {
            let osc2_freq = freq * 2.0_f32.powf(track.osc2_octave) * 2.0_f32.powf(track.osc2_detune / 12.0);
            self.osc[1].init(track.osc2_wave, osc2_freq, sample_rate);
            self.osc[1].mix_level = track.osc2_mix;
        }
        if self.osc_count >= 3 {
            let osc3_freq = freq * 2.0_f32.powf(track.osc3_octave) * 2.0_f32.powf(track.osc3_detune / 12.0);
            self.osc[2].init(track.osc3_wave, osc3_freq, sample_rate);
            self.osc[2].mix_level = track.osc3_mix;
        }

        // Filter
        self.filter.init(track.filter_type, track.cutoff, track.resonance);

        // Amp envelope
        self.amp_env.init(track.amp_a, track.amp_d, track.amp_s, track.amp_r, sample_rate);
        self.amp_env.exponential = true;
        self.amp_env.gate_on();

        // Filter envelope
        self.filter_env.init(track.filt_a, track.filt_d, track.filt_s, track.filt_r, sample_rate);
        self.filter_env.exponential = true;
        self.filter_env_amount = track.filt_env_amount;
        self.filter_env.gate_on();

        // Pitch envelope
        self.pitch_env_amount = track.pitch_env_amount;
        self.pitch_env_level = if track.pitch_env_amount != 0.0 { 1.0 } else { 0.0 };
        self.pitch_env_rate = if track.pitch_env_decay > 0.001 {
            1.0 / (track.pitch_env_decay * sample_rate)
        } else { 1.0 };

        // FM
        self.fm_mod_phase = 0.0;

        // Anti-click
        self.fade_in = 0.0;
        self.fade_in_samples = (0.002 * sample_rate as f64) as i32;
    }

    pub fn note_off(&mut self) {
        self.amp_env.gate_off();
        self.filter_env.gate_off();
    }

    pub fn render_with_params(&mut self, left: &mut [f32], right: &mut [f32], sample_rate: f32, track: &TrackParams) {
        if !self.active { return; }

        let frames = left.len();
        let inv_sr = 1.0 / sample_rate;
        let synth_type = track.synth_type;
        let fm_ratio = track.fm_ratio;
        let fm_index = track.fm_index;

        let mut mono = vec![0.0_f32; frames]; // TODO: use stack buffer

        for i in 0..frames {
            // Pitch envelope
            if self.pitch_env_amount != 0.0 && self.pitch_env_level > 0.0001 {
                let pitch_mult = 2.0_f32.powf(self.pitch_env_amount * self.pitch_env_level / 12.0);
                self.osc[0].phase_inc = self.osc[0].frequency * pitch_mult * inv_sr;
                self.pitch_env_level *= 1.0 - self.pitch_env_rate;
            }

            let osc_out = if synth_type == 1 && fm_ratio > 0.0 && fm_index > 0.0 {
                // FM synthesis
                let mod_freq = self.osc[0].frequency * fm_ratio;
                let mod_out = (TWO_PI * self.fm_mod_phase).sin() * fm_index;
                self.fm_mod_phase += mod_freq * inv_sr;
                if self.fm_mod_phase >= 1.0 { self.fm_mod_phase -= 1.0; }
                let out = (TWO_PI * (self.osc[0].phase + mod_out)).sin();
                self.osc[0].phase += self.osc[0].phase_inc;
                if self.osc[0].phase >= 1.0 { self.osc[0].phase -= 1.0; }
                out
            } else {
                // Additive
                let mut out = 0.0;
                let mut total_mix = 0.0;
                for o in 0..self.osc_count as usize {
                    out += self.osc[o].process_sample() * self.osc[o].mix_level;
                    total_mix += self.osc[o].mix_level;
                }
                if total_mix > 1.0 { out / total_mix } else { out }
            };

            mono[i] = osc_out;
        }

        // Filter with envelope modulation
        let base_cutoff = self.filter.cutoff;
        for i in 0..frames {
            let filt_env = self.filter_env.process_sample();
            let fc = base_cutoff + self.filter_env_amount * filt_env;
            mono[i] = self.filter.process_sample(mono[i], fc, sample_rate);
        }
        self.filter.cutoff = base_cutoff;

        // Amp envelope + pan + fade-in
        let pan_r = (self.pan + 1.0) * 0.5;
        let pan_l = 1.0 - pan_r;

        for i in 0..frames {
            let mut amp = self.amp_env.process_sample();
            if self.fade_in < 1.0 {
                self.fade_in += 1.0 / self.fade_in_samples as f32;
                if self.fade_in > 1.0 { self.fade_in = 1.0; }
                amp *= self.fade_in;
            }
            let sample = (mono[i] * amp * self.velocity).clamp(-1.0, 1.0);
            left[i] += sample * pan_l;
            right[i] += sample * pan_r;
        }

        if self.amp_env.is_idle() {
            self.active = false;
        }
    }
}
