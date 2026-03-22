use std::f32::consts::PI;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FilterType {
    LowPass,
    HighPass,
    BandPass,
}

/// Chamberlin state-variable filter
#[derive(Clone)]
pub struct Filter {
    pub cutoff: f32,
    pub resonance: f32,
    pub filter_type: FilterType,
    // State
    low: f32,
    high: f32,
    band: f32,
}

impl Filter {
    pub fn new() -> Self {
        Self {
            cutoff: 4000.0,
            resonance: 0.3,
            filter_type: FilterType::LowPass,
            low: 0.0,
            high: 0.0,
            band: 0.0,
        }
    }

    pub fn init(&mut self, filter_type: FilterType, cutoff: f32, resonance: f32) {
        self.filter_type = filter_type;
        self.cutoff = cutoff;
        self.resonance = resonance.clamp(0.0, 0.95);
        self.low = 0.0;
        self.high = 0.0;
        self.band = 0.0;
    }

    /// Process a single sample with given cutoff (for per-sample modulation)
    pub fn process_sample(&mut self, input: f32, cutoff: f32, sample_rate: f32) -> f32 {
        let fc = cutoff.clamp(20.0, sample_rate * 0.43);
        let f = (PI * fc / sample_rate).sin() * 2.0;
        let f = f.min(0.95); // stability clamp
        let q = 1.0 - self.resonance.clamp(0.0, 0.95);

        self.low += f * self.band;
        self.high = input - self.low - q * self.band;
        self.band += f * self.high;

        // Clamp state to prevent runaway
        self.low = self.low.clamp(-10.0, 10.0);
        self.band = self.band.clamp(-10.0, 10.0);

        match self.filter_type {
            FilterType::LowPass => self.low,
            FilterType::HighPass => self.high,
            FilterType::BandPass => self.band,
        }
    }

    /// Process a buffer in-place (constant cutoff)
    pub fn process(&mut self, buf: &mut [f32], sample_rate: f32) {
        let fc = self.cutoff.clamp(20.0, sample_rate * 0.43);
        let f = (PI * fc / sample_rate).sin() * 2.0;
        let f = f.min(0.95);
        let q = 1.0 - self.resonance.clamp(0.0, 0.95);

        for sample in buf.iter_mut() {
            self.low += f * self.band;
            self.high = *sample - self.low - q * self.band;
            self.band += f * self.high;

            self.low = self.low.clamp(-10.0, 10.0);
            self.band = self.band.clamp(-10.0, 10.0);

            *sample = match self.filter_type {
                FilterType::LowPass => self.low,
                FilterType::HighPass => self.high,
                FilterType::BandPass => self.band,
            };
        }
    }
}

impl Default for Filter {
    fn default() -> Self { Self::new() }
}
