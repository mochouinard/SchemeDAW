#[derive(Clone, Copy, Debug, PartialEq)]
pub enum EnvStage {
    Idle,
    Attack,
    Decay,
    Sustain,
    Release,
}

/// ADSR envelope with exponential mode for natural-sounding decay
#[derive(Clone)]
pub struct Envelope {
    pub attack: f32,   // seconds
    pub decay: f32,    // seconds
    pub sustain: f32,  // 0.0 - 1.0
    pub release: f32,  // seconds
    pub level: f32,
    pub stage: EnvStage,
    pub exponential: bool,
    sample_rate: f32,
}

impl Envelope {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            attack: 0.01,
            decay: 0.2,
            sustain: 0.7,
            release: 0.3,
            level: 0.0,
            stage: EnvStage::Idle,
            exponential: true,
            sample_rate,
        }
    }

    pub fn init(&mut self, a: f32, d: f32, s: f32, r: f32, sample_rate: f32) {
        self.attack = a;
        self.decay = d;
        self.sustain = s.clamp(0.0, 1.0);
        self.release = r;
        self.level = 0.0;
        self.stage = EnvStage::Idle;
        self.sample_rate = sample_rate;
    }

    pub fn gate_on(&mut self) {
        self.stage = EnvStage::Attack;
    }

    pub fn gate_off(&mut self) {
        if self.stage != EnvStage::Idle {
            self.stage = EnvStage::Release;
        }
    }

    pub fn is_idle(&self) -> bool {
        self.stage == EnvStage::Idle
    }

    pub fn process_sample(&mut self) -> f32 {
        if self.exponential {
            self.process_sample_exp()
        } else {
            self.process_sample_lin()
        }
    }

    fn process_sample_lin(&mut self) -> f32 {
        match self.stage {
            EnvStage::Attack => {
                let rate = if self.attack > 0.001 { 1.0 / (self.attack * self.sample_rate) } else { 1.0 };
                self.level += rate;
                if self.level >= 1.0 {
                    self.level = 1.0;
                    self.stage = EnvStage::Decay;
                }
            }
            EnvStage::Decay => {
                let rate = if self.decay > 0.001 { 1.0 / (self.decay * self.sample_rate) } else { 1.0 };
                self.level -= rate;
                if self.level <= self.sustain {
                    self.level = self.sustain;
                    self.stage = EnvStage::Sustain;
                }
            }
            EnvStage::Sustain => {
                self.level = self.sustain;
            }
            EnvStage::Release => {
                let rate = if self.release > 0.001 { 1.0 / (self.release * self.sample_rate) } else { 1.0 };
                self.level -= rate;
                if self.level <= 0.0 {
                    self.level = 0.0;
                    self.stage = EnvStage::Idle;
                }
            }
            EnvStage::Idle => {
                self.level = 0.0;
            }
        }
        self.level
    }

    fn process_sample_exp(&mut self) -> f32 {
        match self.stage {
            EnvStage::Attack => {
                let rate = if self.attack > 0.001 { 1.0 / (self.attack * self.sample_rate) } else { 1.0 };
                self.level += rate;
                if self.level >= 1.0 {
                    self.level = 1.0;
                    self.stage = EnvStage::Decay;
                }
            }
            EnvStage::Decay => {
                let coeff = (-1.0 / (self.decay * self.sample_rate + 1.0)).exp();
                self.level = self.sustain + (self.level - self.sustain) * coeff;
                if (self.level - self.sustain).abs() < 0.001 {
                    self.level = self.sustain;
                    self.stage = EnvStage::Sustain;
                }
            }
            EnvStage::Sustain => {
                self.level = self.sustain;
            }
            EnvStage::Release => {
                let coeff = (-1.0 / (self.release * self.sample_rate + 1.0)).exp();
                self.level *= coeff;
                if self.level < 0.0001 {
                    self.level = 0.0;
                    self.stage = EnvStage::Idle;
                }
            }
            EnvStage::Idle => {
                self.level = 0.0;
            }
        }
        self.level
    }
}
