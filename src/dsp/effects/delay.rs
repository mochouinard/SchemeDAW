/// Stereo delay with feedback
#[derive(Clone)]
pub struct Delay {
    buffer_l: Vec<f32>,
    buffer_r: Vec<f32>,
    write_pos: usize,
    pub delay_time: f32,  // seconds
    pub feedback: f32,    // 0.0 - 0.95
    pub mix: f32,         // dry/wet
    sample_rate: f32,
}

impl Delay {
    pub fn new(sample_rate: f32) -> Self {
        let max_samples = (sample_rate * 2.0) as usize; // 2 seconds max
        Self {
            buffer_l: vec![0.0; max_samples],
            buffer_r: vec![0.0; max_samples],
            write_pos: 0,
            delay_time: 0.375,
            feedback: 0.4,
            mix: 0.3,
            sample_rate,
        }
    }

    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let buf_size = self.buffer_l.len();
        let delay_samples = ((self.delay_time * self.sample_rate) as usize).min(buf_size - 1).max(1);

        for i in 0..left.len() {
            let read_pos = (self.write_pos + buf_size - delay_samples) % buf_size;

            let delayed_l = self.buffer_l[read_pos];
            let delayed_r = self.buffer_r[read_pos];

            self.buffer_l[self.write_pos] = left[i] + delayed_l * self.feedback;
            self.buffer_r[self.write_pos] = right[i] + delayed_r * self.feedback;

            left[i] = left[i] * (1.0 - self.mix) + delayed_l * self.mix;
            right[i] = right[i] * (1.0 - self.mix) + delayed_r * self.mix;

            self.write_pos = (self.write_pos + 1) % buf_size;
        }
    }
}
