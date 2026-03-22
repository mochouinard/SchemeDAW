pub mod delay;
pub mod reverb;
pub mod distortion;

use delay::Delay;
use reverb::Reverb;
use distortion::Distortion;

/// Effect slot - enum dispatch avoids vtable overhead in audio hot path
#[derive(Clone)]
pub enum EffectSlot {
    None,
    Delay(Delay),
    Reverb(Reverb),
    Distortion(Distortion),
}

impl EffectSlot {
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        match self {
            EffectSlot::None => {}
            EffectSlot::Delay(d) => d.process(left, right),
            EffectSlot::Reverb(r) => r.process(left, right),
            EffectSlot::Distortion(d) => d.process(left, right),
        }
    }

    pub fn is_active(&self) -> bool {
        !matches!(self, EffectSlot::None)
    }
}

/// Chain of up to 8 effects per track
pub struct EffectChain {
    pub slots: [EffectSlot; 8],
    pub count: usize,
}

impl EffectChain {
    pub fn new() -> Self {
        Self {
            slots: std::array::from_fn(|_| EffectSlot::None),
            count: 0,
        }
    }

    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        for i in 0..self.count {
            self.slots[i].process(left, right);
        }
    }
}
