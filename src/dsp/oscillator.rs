use std::f32::consts::PI;

const TWO_PI: f32 = 2.0 * PI;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Waveform {
    Sine,
    Saw,
    Square,
    Triangle,
    Noise,
}

impl Waveform {
    pub fn from_index(i: u8) -> Self {
        match i {
            0 => Waveform::Sine,
            1 => Waveform::Saw,
            2 => Waveform::Square,
            3 => Waveform::Triangle,
            4 => Waveform::Noise,
            _ => Waveform::Sine,
        }
    }
}

#[derive(Clone)]
pub struct Oscillator {
    pub phase: f32,
    pub phase_inc: f32,
    pub frequency: f32,
    pub waveform: Waveform,
    pub detune: f32,      // semitones
    pub mix_level: f32,   // 0.0 - 1.0
    noise_seed: u32,
}

impl Oscillator {
    pub fn new() -> Self {
        Self {
            phase: 0.0,
            phase_inc: 0.0,
            frequency: 440.0,
            waveform: Waveform::Saw,
            detune: 0.0,
            mix_level: 1.0,
            noise_seed: 12345,
        }
    }

    pub fn init(&mut self, waveform: Waveform, frequency: f32, sample_rate: f32) {
        self.phase = 0.0;
        self.waveform = waveform;
        self.frequency = frequency;
        let detune_mult = 2.0_f32.powf(self.detune / 12.0);
        self.phase_inc = (frequency * detune_mult) / sample_rate;
    }

    pub fn set_frequency(&mut self, frequency: f32, sample_rate: f32) {
        self.frequency = frequency;
        let detune_mult = 2.0_f32.powf(self.detune / 12.0);
        self.phase_inc = (frequency * detune_mult) / sample_rate;
    }

    pub fn process_sample(&mut self) -> f32 {
        let out = match self.waveform {
            Waveform::Sine => (TWO_PI * self.phase).sin(),
            Waveform::Saw => 2.0 * self.phase - 1.0,
            Waveform::Square => if self.phase < 0.5 { 1.0 } else { -1.0 },
            Waveform::Triangle => 4.0 * (self.phase - 0.5).abs() - 1.0,
            Waveform::Noise => {
                self.noise_seed = self.noise_seed.wrapping_mul(1664525).wrapping_add(1013904223);
                (self.noise_seed as i32) as f32 / i32::MAX as f32
            }
        };

        self.phase += self.phase_inc;
        if self.phase >= 1.0 { self.phase -= 1.0; }

        out * self.mix_level
    }
}

impl Default for Oscillator {
    fn default() -> Self { Self::new() }
}
