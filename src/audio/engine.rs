use crate::audio::command::{AudioCommand, CmdType, RingBuffer};
use crate::audio::track::{Track, MAX_TRACKS};
use crate::audio::preset::load_preset;
use crate::dsp::sample::SampleEngine;
use crate::dsp::oscillator::Waveform;
use crate::dsp::filter::FilterType;

/// Main audio engine - lives on the audio thread
pub struct AudioEngine {
    pub tracks: Vec<Track>,
    pub sample_engine: SampleEngine,
    pub master_volume: f32,
    pub sample_rate: f32,
    voice_counter: u32,
}

impl AudioEngine {
    pub fn new(sample_rate: f32) -> Self {
        let mut tracks = Vec::with_capacity(MAX_TRACKS);
        for _ in 0..MAX_TRACKS {
            tracks.push(Track::new(sample_rate));
        }

        Self {
            tracks,
            sample_engine: SampleEngine::new(),
            master_volume: 0.8,
            sample_rate,
            voice_counter: 0,
        }
    }

    /// Process all pending commands from the ring buffer
    pub fn process_commands(&mut self, ring: &RingBuffer) {
        while let Some(cmd) = ring.read() {
            self.handle_command(cmd);
        }
    }

    fn handle_command(&mut self, cmd: AudioCommand) {
        let t = cmd.track as usize;

        match cmd.cmd {
            x if x == CmdType::NoteOn as u8 => {
                if t < MAX_TRACKS {
                    self.tracks[t].note_on(cmd.param1, cmd.param2, self.sample_rate, &mut self.voice_counter);
                }
            }
            x if x == CmdType::NoteOff as u8 => {
                if t < MAX_TRACKS { self.tracks[t].note_off(cmd.param1); }
            }
            x if x == CmdType::AllNotesOff as u8 => {
                if t < MAX_TRACKS { self.tracks[t].all_notes_off(); }
            }
            x if x == CmdType::SetVolume as u8 => {
                if t < MAX_TRACKS { self.tracks[t].volume = cmd.fvalue; }
            }
            x if x == CmdType::SetPan as u8 => {
                if t < MAX_TRACKS { self.tracks[t].pan = cmd.fvalue; }
            }
            x if x == CmdType::MuteTrack as u8 => {
                if t < MAX_TRACKS { self.tracks[t].mute = cmd.param1 != 0; }
            }
            x if x == CmdType::SoloTrack as u8 => {
                if t < MAX_TRACKS { self.tracks[t].solo = cmd.param1 != 0; }
            }
            x if x == CmdType::LoadPreset as u8 => {
                if t < MAX_TRACKS { load_preset(&mut self.tracks[t], cmd.param1 as usize); }
            }
            x if x == CmdType::SetFilter as u8 => {
                if t < MAX_TRACKS {
                    match cmd.param1 {
                        0 => self.tracks[t].cutoff = cmd.fvalue,
                        1 => self.tracks[t].resonance = cmd.fvalue,
                        2 => self.tracks[t].filter_type = match cmd.param2 {
                            0 => FilterType::LowPass,
                            1 => FilterType::HighPass,
                            2 => FilterType::BandPass,
                            _ => FilterType::LowPass,
                        },
                        _ => {}
                    }
                }
            }
            x if x == CmdType::SetWaveform as u8 => {
                if t < MAX_TRACKS { self.tracks[t].waveform = Waveform::from_index(cmd.param1); }
            }
            x if x == CmdType::MasterVolume as u8 => {
                self.master_volume = cmd.fvalue;
            }
            x if x == CmdType::SampleTrigger as u8 => {
                self.sample_engine.trigger(t, cmd.param1 as f32 / 127.0, cmd.fvalue);
            }
            x if x == CmdType::SampleStop as u8 => {
                self.sample_engine.stop_all();
            }
            _ => {}
        }
    }

    /// Render audio into interleaved stereo buffer
    pub fn render(&mut self, output: &mut [f32]) {
        let frames = output.len() / 2;

        // Zero output
        for s in output.iter_mut() { *s = 0.0; }

        // Check solo state
        let any_solo = self.tracks.iter().any(|t| t.solo);

        let mut left_buf = vec![0.0_f32; frames];
        let mut right_buf = vec![0.0_f32; frames];

        for t in 0..MAX_TRACKS {
            if self.tracks[t].mute { continue; }
            if any_solo && !self.tracks[t].solo { continue; }

            self.tracks[t].render(&mut left_buf, &mut right_buf, self.sample_rate);

            // Mix into interleaved output
            for i in 0..frames {
                output[i * 2] += left_buf[i];
                output[i * 2 + 1] += right_buf[i];
            }
        }

        // Render samples
        for s in left_buf.iter_mut() { *s = 0.0; }
        for s in right_buf.iter_mut() { *s = 0.0; }
        self.sample_engine.render(&mut left_buf, &mut right_buf);
        for i in 0..frames {
            output[i * 2] += left_buf[i];
            output[i * 2 + 1] += right_buf[i];
        }

        // Master volume + soft clipping
        for s in output.iter_mut() {
            *s *= self.master_volume;
            if *s > 0.8 || *s < -0.8 {
                *s = s.tanh();
            }
        }
    }
}
