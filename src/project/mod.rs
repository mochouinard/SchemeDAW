use serde::{Serialize, Deserialize};
use crate::sequencer::{PatternBank, Arrangement};

#[derive(Serialize, Deserialize)]
pub struct Project {
    pub version: u32,
    pub bpm: f32,
    pub master_volume: f32,
    pub track_presets: Vec<usize>,
    pub track_volumes: Vec<f32>,
    pub track_notes: Vec<u8>,
    pub track_mutes: Vec<bool>,
    pub track_solos: Vec<bool>,
    pub pattern_bank: PatternBank,
    pub arrangement: Arrangement,
}

impl Project {
    pub fn save(&self, filename: &str) -> Result<(), String> {
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Serialize error: {}", e))?;
        std::fs::write(filename, json)
            .map_err(|e| format!("Write error: {}", e))?;
        Ok(())
    }

    pub fn load(filename: &str) -> Result<Self, String> {
        let data = std::fs::read_to_string(filename)
            .map_err(|e| format!("Read error: {}", e))?;
        serde_json::from_str(&data)
            .map_err(|e| format!("Parse error: {}", e))
    }
}
