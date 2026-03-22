use crate::dsp::oscillator::Waveform;
use crate::dsp::filter::FilterType;
use crate::audio::track::Track;

pub const PRESET_NAMES: [&str; 16] = [
    "Supersaw Lead",
    "Deep Sub Bass",
    "Acid Bass 303",
    "Warm Pad",
    "FM Bell",
    "FM E.Piano",
    "808 Kick",
    "Snare",
    "HiHat Closed",
    "HiHat Open",
    "Clap",
    "Pluck",
    "Stab",
    "Reese Bass",
    "Strings",
    "Brass",
];

pub fn load_preset(track: &mut Track, preset_id: usize) {
    // Preserve mix state
    let vol = track.volume;
    let pan = track.pan;
    let mute = track.mute;
    let solo = track.solo;

    match preset_id {
        0 => { // Supersaw Lead
            track.synth_type = 0;
            track.osc_count = 3;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc3_wave = Waveform::Saw;
            track.osc2_detune = 0.12;
            track.osc3_detune = -0.12;
            track.osc2_mix = 0.9;
            track.osc3_mix = 0.9;
            track.cutoff = 5000.0;
            track.resonance = 0.25;
            track.filt_env_amount = 3000.0;
            track.amp_a = 0.01; track.amp_d = 0.15;
            track.amp_s = 0.8; track.amp_r = 0.4;
            track.filt_a = 0.01; track.filt_d = 0.3;
            track.filt_s = 0.4; track.filt_r = 0.5;
        }
        1 => { // Deep Sub Bass
            track.synth_type = 0;
            track.osc_count = 2;
            track.waveform = Waveform::Sine;
            track.osc2_wave = Waveform::Sine;
            track.osc2_octave = -1.0;
            track.osc2_mix = 0.7;
            track.cutoff = 500.0;
            track.resonance = 0.1;
            track.filt_env_amount = 200.0;
            track.amp_a = 0.005; track.amp_d = 0.3;
            track.amp_s = 0.6; track.amp_r = 0.2;
        }
        2 => { // Acid Bass 303
            track.synth_type = 0;
            track.osc_count = 1;
            track.waveform = Waveform::Saw;
            track.cutoff = 400.0;
            track.resonance = 0.75;
            track.filt_env_amount = 8000.0;
            track.amp_a = 0.003; track.amp_d = 0.15;
            track.amp_s = 0.0; track.amp_r = 0.08;
            track.filt_a = 0.003; track.filt_d = 0.12;
            track.filt_s = 0.0; track.filt_r = 0.1;
        }
        3 => { // Warm Pad
            track.synth_type = 0;
            track.osc_count = 3;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc3_wave = Waveform::Triangle;
            track.osc2_detune = 0.08;
            track.osc3_detune = -0.05;
            track.osc3_octave = 1.0;
            track.osc2_mix = 0.8;
            track.osc3_mix = 0.3;
            track.cutoff = 2500.0;
            track.resonance = 0.15;
            track.filt_env_amount = 1500.0;
            track.amp_a = 0.6; track.amp_d = 0.5;
            track.amp_s = 0.75; track.amp_r = 1.5;
            track.filt_a = 0.5; track.filt_d = 0.8;
            track.filt_s = 0.4; track.filt_r = 1.5;
        }
        4 => { // FM Bell
            track.synth_type = 1;
            track.osc_count = 1;
            track.waveform = Waveform::Sine;
            track.fm_ratio = 3.5;
            track.fm_index = 5.0;
            track.cutoff = 12000.0;
            track.resonance = 0.05;
            track.filt_env_amount = 0.0;
            track.amp_a = 0.001; track.amp_d = 2.5;
            track.amp_s = 0.0; track.amp_r = 2.0;
        }
        5 => { // FM Electric Piano
            track.synth_type = 1;
            track.osc_count = 1;
            track.waveform = Waveform::Sine;
            track.fm_ratio = 7.0;
            track.fm_index = 2.5;
            track.cutoff = 8000.0;
            track.resonance = 0.1;
            track.filt_env_amount = 0.0;
            track.amp_a = 0.001; track.amp_d = 1.2;
            track.amp_s = 0.25; track.amp_r = 0.8;
        }
        6 => { // 808 Kick
            track.synth_type = 0;
            track.osc_count = 1;
            track.waveform = Waveform::Sine;
            track.cutoff = 20000.0;
            track.resonance = 0.0;
            track.filt_env_amount = 0.0;
            track.amp_a = 0.001; track.amp_d = 0.5;
            track.amp_s = 0.0; track.amp_r = 0.3;
            track.pitch_env_amount = 48.0;
            track.pitch_env_decay = 0.07;
        }
        7 => { // Snare
            track.synth_type = 0;
            track.osc_count = 2;
            track.waveform = Waveform::Sine;
            track.osc2_wave = Waveform::Noise;
            track.osc2_mix = 1.2;
            track.cutoff = 6000.0;
            track.resonance = 0.1;
            track.filt_env_amount = 3000.0;
            track.amp_a = 0.001; track.amp_d = 0.18;
            track.amp_s = 0.0; track.amp_r = 0.1;
            track.filt_a = 0.001; track.filt_d = 0.08;
            track.filt_s = 0.0; track.filt_r = 0.05;
            track.pitch_env_amount = 12.0;
            track.pitch_env_decay = 0.02;
        }
        8 => { // HiHat Closed
            track.synth_type = 0;
            track.osc_count = 1;
            track.waveform = Waveform::Noise;
            track.cutoff = 10000.0;
            track.resonance = 0.3;
            track.filter_type = FilterType::HighPass;
            track.filt_env_amount = 2000.0;
            track.amp_a = 0.001; track.amp_d = 0.06;
            track.amp_s = 0.0; track.amp_r = 0.04;
        }
        9 => { // HiHat Open
            track.synth_type = 0;
            track.osc_count = 1;
            track.waveform = Waveform::Noise;
            track.cutoff = 9000.0;
            track.resonance = 0.35;
            track.filter_type = FilterType::HighPass;
            track.filt_env_amount = 3000.0;
            track.amp_a = 0.001; track.amp_d = 0.35;
            track.amp_s = 0.0; track.amp_r = 0.25;
        }
        10 => { // Clap
            track.synth_type = 0;
            track.osc_count = 1;
            track.waveform = Waveform::Noise;
            track.cutoff = 3000.0;
            track.resonance = 0.2;
            track.filter_type = FilterType::BandPass;
            track.filt_env_amount = 4000.0;
            track.amp_a = 0.001; track.amp_d = 0.2;
            track.amp_s = 0.0; track.amp_r = 0.15;
        }
        11 => { // Pluck
            track.synth_type = 0;
            track.osc_count = 2;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Square;
            track.osc2_detune = 0.05;
            track.osc2_mix = 0.6;
            track.cutoff = 6000.0;
            track.resonance = 0.35;
            track.filt_env_amount = 6000.0;
            track.amp_a = 0.001; track.amp_d = 0.4;
            track.amp_s = 0.0; track.amp_r = 0.3;
            track.filt_a = 0.001; track.filt_d = 0.2;
            track.filt_s = 0.0; track.filt_r = 0.15;
        }
        12 => { // Stab
            track.synth_type = 0;
            track.osc_count = 3;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc3_wave = Waveform::Saw;
            track.osc2_detune = 0.15;
            track.osc3_detune = -0.15;
            track.osc2_mix = 0.9;
            track.osc3_mix = 0.9;
            track.cutoff = 3000.0;
            track.resonance = 0.4;
            track.filt_env_amount = 5000.0;
            track.amp_a = 0.001; track.amp_d = 0.2;
            track.amp_s = 0.0; track.amp_r = 0.15;
        }
        13 => { // Reese Bass
            track.synth_type = 0;
            track.osc_count = 2;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc2_detune = 0.06;
            track.osc2_mix = 1.0;
            track.cutoff = 1200.0;
            track.resonance = 0.35;
            track.filt_env_amount = 2000.0;
            track.amp_a = 0.01; track.amp_d = 0.3;
            track.amp_s = 0.7; track.amp_r = 0.3;
        }
        14 => { // Strings
            track.synth_type = 0;
            track.osc_count = 3;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc3_wave = Waveform::Saw;
            track.osc2_detune = 0.1;
            track.osc3_detune = -0.1;
            track.osc2_mix = 0.85;
            track.osc3_mix = 0.85;
            track.cutoff = 3500.0;
            track.resonance = 0.1;
            track.filt_env_amount = 1000.0;
            track.amp_a = 0.8; track.amp_d = 0.3;
            track.amp_s = 0.85; track.amp_r = 1.0;
        }
        15 => { // Brass
            track.synth_type = 0;
            track.osc_count = 2;
            track.waveform = Waveform::Saw;
            track.osc2_wave = Waveform::Saw;
            track.osc2_detune = 0.03;
            track.osc2_mix = 0.9;
            track.cutoff = 2000.0;
            track.resonance = 0.2;
            track.filt_env_amount = 6000.0;
            track.amp_a = 0.05; track.amp_d = 0.2;
            track.amp_s = 0.8; track.amp_r = 0.2;
        }
        _ => {}
    }

    // Reset pitch/fm defaults for non-drum presets
    if preset_id < 6 || preset_id >= 11 {
        if track.pitch_env_amount == 0.0 { track.pitch_env_decay = 0.1; }
        if track.fm_index == 0.0 { track.fm_ratio = 2.0; }
    }

    track.volume = vol;
    track.pan = pan;
    track.mute = mute;
    track.solo = solo;
}
