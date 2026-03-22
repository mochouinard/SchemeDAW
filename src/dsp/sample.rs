/// A loaded audio sample
pub struct Sample {
    pub data: Vec<f32>,    // interleaved stereo
    pub frames: usize,
    pub channels: u16,
    pub sample_rate: u32,
    pub name: String,
}

/// A playing sample voice
#[derive(Clone)]
pub struct SampleVoice {
    pub sample_id: usize,
    pub play_pos: f32,
    pub volume: f32,
    pub pan: f32,
    pub pitch: f32,
    pub playing: bool,
    pub looping: bool,
}

impl SampleVoice {
    pub fn new() -> Self {
        Self {
            sample_id: 0,
            play_pos: 0.0,
            volume: 1.0,
            pan: 0.0,
            pitch: 1.0,
            playing: false,
            looping: false,
        }
    }
}

pub const MAX_SAMPLES: usize = 256;
pub const MAX_SAMPLE_VOICES: usize = 32;

/// Sample engine: manages loaded samples and playback voices
pub struct SampleEngine {
    pub slots: Vec<Option<Sample>>,
    pub voices: Vec<SampleVoice>,
}

impl SampleEngine {
    pub fn new() -> Self {
        let mut slots = Vec::with_capacity(MAX_SAMPLES);
        slots.resize_with(MAX_SAMPLES, || None);

        let mut voices = Vec::with_capacity(MAX_SAMPLE_VOICES);
        for _ in 0..MAX_SAMPLE_VOICES {
            voices.push(SampleVoice::new());
        }

        Self { slots, voices }
    }

    pub fn load_wav(&mut self, filename: &str, slot: usize) -> Result<(), String> {
        if slot >= MAX_SAMPLES { return Err("Invalid slot".into()); }

        let reader = hound::WavReader::open(filename)
            .map_err(|e| format!("Failed to open {}: {}", filename, e))?;

        let spec = reader.spec();
        let mut data: Vec<f32> = Vec::new();

        match spec.sample_format {
            hound::SampleFormat::Float => {
                for s in reader.into_samples::<f32>() {
                    data.push(s.map_err(|e| e.to_string())?);
                }
            }
            hound::SampleFormat::Int => {
                let max_val = (1 << (spec.bits_per_sample - 1)) as f32;
                for s in reader.into_samples::<i32>() {
                    let sample = s.map_err(|e| e.to_string())?;
                    data.push(sample as f32 / max_val);
                }
            }
        }

        // Convert mono to stereo if needed
        if spec.channels == 1 {
            let mono = data.clone();
            data.clear();
            for s in mono {
                data.push(s);
                data.push(s);
            }
        }

        let frames = data.len() / 2;
        let name = std::path::Path::new(filename)
            .file_name()
            .map(|f| f.to_string_lossy().into_owned())
            .unwrap_or_else(|| filename.to_string());

        self.slots[slot] = Some(Sample {
            data,
            frames,
            channels: 2,
            sample_rate: spec.sample_rate,
            name,
        });

        Ok(())
    }

    pub fn trigger(&mut self, slot: usize, volume: f32, pitch: f32) -> Option<usize> {
        if slot >= MAX_SAMPLES || self.slots[slot].is_none() { return None; }

        // Find free voice
        let voice_id = self.voices.iter().position(|v| !v.playing)
            .unwrap_or(0); // steal first if all busy

        self.voices[voice_id] = SampleVoice {
            sample_id: slot,
            play_pos: 0.0,
            volume,
            pan: 0.0,
            pitch: if pitch > 0.0 { pitch } else { 1.0 },
            playing: true,
            looping: false,
        };

        Some(voice_id)
    }

    pub fn stop_all(&mut self) {
        for v in &mut self.voices {
            v.playing = false;
        }
    }

    pub fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        for voice in &mut self.voices {
            if !voice.playing { continue; }

            let sample = match &self.slots[voice.sample_id] {
                Some(s) => s,
                None => { voice.playing = false; continue; }
            };

            let pan_r = (voice.pan + 1.0) * 0.5;
            let pan_l = 1.0 - pan_r;

            for i in 0..left.len() {
                let pos = voice.play_pos as usize;
                if pos >= sample.frames {
                    if voice.looping {
                        voice.play_pos = 0.0;
                    } else {
                        voice.playing = false;
                        break;
                    }
                }
                let pos = voice.play_pos as usize;
                if pos >= sample.frames { break; }

                let sl = sample.data[pos * 2] * voice.volume;
                let sr = sample.data[pos * 2 + 1] * voice.volume;

                left[i] += sl * pan_l;
                right[i] += sr * pan_r;

                voice.play_pos += voice.pitch;
            }
        }
    }
}
