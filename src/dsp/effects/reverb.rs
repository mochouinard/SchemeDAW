/// Schroeder reverb: 4 parallel comb filters + 2 series allpass filters
#[derive(Clone)]
pub struct Reverb {
    comb_l: [DelayLine; 4],
    comb_r: [DelayLine; 4],
    allpass_l: [DelayLine; 2],
    allpass_r: [DelayLine; 2],
    comb_feedback: [f32; 4],
    allpass_feedback: [f32; 2],
    damp_state_l: [f32; 4],
    damp_state_r: [f32; 4],
    pub room_size: f32,
    pub damping: f32,
    pub mix: f32,
    pub width: f32,
}

#[derive(Clone)]
struct DelayLine {
    buffer: Vec<f32>,
    pos: usize,
}

impl DelayLine {
    fn new(size: usize) -> Self {
        Self { buffer: vec![0.0; size], pos: 0 }
    }
    fn read(&self) -> f32 { self.buffer[self.pos] }
    fn write(&mut self, val: f32) {
        self.buffer[self.pos] = val;
        self.pos = (self.pos + 1) % self.buffer.len();
    }
}

const COMB_LENGTHS: [usize; 4] = [1116, 1188, 1277, 1356];
const ALLPASS_LENGTHS: [usize; 2] = [556, 441];
const STEREO_SPREAD: usize = 23;

impl Reverb {
    pub fn new(sample_rate: f32) -> Self {
        let scale = sample_rate / 44100.0;
        let comb_l = std::array::from_fn(|i| DelayLine::new((COMB_LENGTHS[i] as f32 * scale) as usize));
        let comb_r = std::array::from_fn(|i| DelayLine::new((COMB_LENGTHS[i] as f32 * scale) as usize + STEREO_SPREAD));
        let allpass_l = std::array::from_fn(|i| DelayLine::new((ALLPASS_LENGTHS[i] as f32 * scale) as usize));
        let allpass_r = std::array::from_fn(|i| DelayLine::new((ALLPASS_LENGTHS[i] as f32 * scale) as usize + STEREO_SPREAD));

        Self {
            comb_l, comb_r, allpass_l, allpass_r,
            comb_feedback: [0.84; 4],
            allpass_feedback: [0.5; 2],
            damp_state_l: [0.0; 4],
            damp_state_r: [0.0; 4],
            room_size: 0.7,
            damping: 0.5,
            mix: 0.3,
            width: 1.0,
        }
    }

    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let damp1 = self.damping;
        let damp2 = 1.0 - damp1;
        let feedback = 0.7 + 0.28 * self.room_size;

        for i in 0..left.len() {
            let input = (left[i] + right[i]) * 0.5;
            let mut out_l = 0.0_f32;
            let mut out_r = 0.0_f32;

            for c in 0..4 {
                let cl = self.comb_l[c].read();
                self.damp_state_l[c] = cl * damp2 + self.damp_state_l[c] * damp1;
                self.comb_l[c].write(input + self.damp_state_l[c] * feedback);
                out_l += cl;

                let cr = self.comb_r[c].read();
                self.damp_state_r[c] = cr * damp2 + self.damp_state_r[c] * damp1;
                self.comb_r[c].write(input + self.damp_state_r[c] * feedback);
                out_r += cr;
            }

            for a in 0..2 {
                let al = self.allpass_l[a].read();
                self.allpass_l[a].write(out_l + al * self.allpass_feedback[a]);
                out_l = al - out_l * self.allpass_feedback[a];

                let ar = self.allpass_r[a].read();
                self.allpass_r[a].write(out_r + ar * self.allpass_feedback[a]);
                out_r = ar - out_r * self.allpass_feedback[a];
            }

            let wet_l = out_l * self.width + out_r * (1.0 - self.width);
            let wet_r = out_r * self.width + out_l * (1.0 - self.width);

            left[i] = left[i] * (1.0 - self.mix) + wet_l * self.mix * 0.5;
            right[i] = right[i] * (1.0 - self.mix) + wet_r * self.mix * 0.5;
        }
    }
}
