pub mod oscillator;
pub mod filter;
pub mod envelope;
pub mod effects;
pub mod sample;

/// Convert MIDI note number to frequency in Hz
pub fn midi_to_freq(note: u8) -> f32 {
    440.0 * 2.0_f32.powf((note as f32 - 69.0) / 12.0)
}

/// Note name from MIDI number
pub fn midi_to_name(note: u8) -> String {
    const NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    let name = NAMES[(note % 12) as usize];
    let octave = (note / 12) as i8 - 1;
    format!("{}{}", name, octave)
}
