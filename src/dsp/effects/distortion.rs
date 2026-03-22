use std::f32::consts::PI;

/// Soft-clip distortion with tone filter
#[derive(Clone)]
pub struct Distortion {
    pub drive: f32,        // 1.0 - 100.0
    pub tone: f32,         // LP cutoff after distortion
    pub mix: f32,          // dry/wet
    pub output_gain: f32,
    filter_state_l: f32,
    filter_state_r: f32,
    sample_rate: f32,
}

impl Distortion {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            drive: 5.0,
            tone: 8000.0,
            mix: 0.5,
            output_gain: 0.5,
            filter_state_l: 0.0,
            filter_state_r: 0.0,
            sample_rate,
        }
    }

    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let fc = (PI * self.tone / self.sample_rate).sin() * 2.0;

        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];

            let mut wet_l = (dry_l * self.drive).tanh() * self.output_gain;
            let mut wet_r = (dry_r * self.drive).tanh() * self.output_gain;

            // Tone filter
            self.filter_state_l += fc * (wet_l - self.filter_state_l);
            self.filter_state_r += fc * (wet_r - self.filter_state_r);
            wet_l = self.filter_state_l;
            wet_r = self.filter_state_r;

            left[i] = dry_l * (1.0 - self.mix) + wet_l * self.mix;
            right[i] = dry_r * (1.0 - self.mix) + wet_r * self.mix;
        }
    }
}
