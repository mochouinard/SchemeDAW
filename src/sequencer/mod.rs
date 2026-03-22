pub mod pattern;

use serde::{Serialize, Deserialize};

pub const MAX_PATTERNS: usize = 16;
pub const MAX_ARRANGEMENT: usize = 64;
pub const GRID_ROWS: usize = 8;
pub const GRID_COLS: usize = 16;

/// A pattern bank holds multiple patterns
#[derive(Clone, Serialize, Deserialize)]
pub struct PatternBank {
    pub patterns: Vec<pattern::Pattern>,
    pub num_active: usize,
}

impl PatternBank {
    pub fn new() -> Self {
        let mut patterns = Vec::with_capacity(MAX_PATTERNS);
        for i in 0..MAX_PATTERNS {
            patterns.push(pattern::Pattern::new(format!("Pattern {}", i + 1)));
        }
        Self { patterns, num_active: 4 }
    }
}

/// Song arrangement
#[derive(Clone, Serialize, Deserialize)]
pub struct Arrangement {
    pub slots: Vec<usize>,   // pattern indices
    pub length: usize,
}

impl Arrangement {
    pub fn new() -> Self {
        let mut slots = vec![0; MAX_ARRANGEMENT];
        // Default: P0, P1, P2, P3
        for i in 0..4 { slots[i] = i; }
        Self { slots, length: 4 }
    }
}
