use serde::{Serialize, Deserialize};
use super::{GRID_ROWS, GRID_COLS};

/// A pattern: 2D grid of note values (0 = empty, 1-127 = MIDI note)
#[derive(Clone, Serialize, Deserialize)]
pub struct Pattern {
    pub name: String,
    pub grid: Vec<Vec<u8>>,  // [row][col] = MIDI note or 0
    pub rows: usize,
    pub cols: usize,
}

impl Pattern {
    pub fn new(name: String) -> Self {
        let grid = vec![vec![0u8; GRID_COLS]; GRID_ROWS];
        Self { name, grid, rows: GRID_ROWS, cols: GRID_COLS }
    }

    pub fn get(&self, row: usize, col: usize) -> u8 {
        if row < self.rows && col < self.cols {
            self.grid[row][col]
        } else { 0 }
    }

    pub fn set(&mut self, row: usize, col: usize, note: u8) {
        if row < self.rows && col < self.cols {
            self.grid[row][col] = note;
        }
    }

    pub fn clear(&mut self) {
        for row in &mut self.grid {
            for cell in row.iter_mut() { *cell = 0; }
        }
    }

    pub fn copy_from(&mut self, other: &Pattern) {
        for r in 0..self.rows.min(other.rows) {
            for c in 0..self.cols.min(other.cols) {
                self.grid[r][c] = other.grid[r][c];
            }
        }
    }
}
