use std::sync::atomic::{AtomicUsize, Ordering};

/// Command types for GUI -> Audio thread communication
#[derive(Clone, Copy, Debug)]
#[repr(u8)]
pub enum CmdType {
    NoteOn = 0x01,
    NoteOff = 0x02,
    AllNotesOff = 0x03,
    SetVolume = 0x04,
    SetPan = 0x05,
    MuteTrack = 0x06,
    SoloTrack = 0x07,
    LoadPreset = 0x08,
    SetFilter = 0x09,      // param1: 0=cutoff, 1=reso, 2=type
    SetEnvelope = 0x0A,    // param1: 0=amp, 1=filter; param2: 0=A,1=D,2=S,3=R
    SetWaveform = 0x0B,
    SetOscCount = 0x0C,
    SetOsc2 = 0x0D,        // param1: 0=wave, 1=detune, 2=mix, 3=octave
    SetOsc3 = 0x0E,
    SetFm = 0x0F,          // param1: 0=ratio, 1=index
    SetPitchEnv = 0x10,    // param1: 0=amount, 1=decay
    SetSynthType = 0x11,
    MasterVolume = 0x20,
    SampleTrigger = 0x21,
    SampleStop = 0x22,
}

/// Fixed-size command message
#[derive(Clone, Copy)]
#[repr(C)]
pub struct AudioCommand {
    pub cmd: u8,
    pub track: u8,
    pub param1: u8,
    pub param2: u8,
    pub fvalue: f32,
}

impl AudioCommand {
    pub fn new(cmd: CmdType, track: u8, p1: u8, p2: u8, fval: f32) -> Self {
        Self { cmd: cmd as u8, track, param1: p1, param2: p2, fvalue: fval }
    }
}

impl Default for AudioCommand {
    fn default() -> Self {
        Self { cmd: 0, track: 0, param1: 0, param2: 0, fvalue: 0.0 }
    }
}

/// Lock-free Single-Producer Single-Consumer ring buffer
pub const RING_SIZE: usize = 4096;

pub struct RingBuffer {
    buffer: [AudioCommand; RING_SIZE],
    write_pos: AtomicUsize,
    read_pos: AtomicUsize,
}

impl RingBuffer {
    pub fn new() -> Self {
        Self {
            buffer: [AudioCommand::default(); RING_SIZE],
            write_pos: AtomicUsize::new(0),
            read_pos: AtomicUsize::new(0),
        }
    }

    /// Write a command (producer side - GUI thread)
    pub fn write(&self, cmd: AudioCommand) -> bool {
        let wp = self.write_pos.load(Ordering::Relaxed);
        let next_wp = (wp + 1) % RING_SIZE;
        let rp = self.read_pos.load(Ordering::Acquire);

        if next_wp == rp {
            return false; // full
        }

        // Safety: single producer, so only we write to buffer[wp]
        unsafe {
            let ptr = self.buffer.as_ptr() as *mut AudioCommand;
            ptr.add(wp).write(cmd);
        }

        self.write_pos.store(next_wp, Ordering::Release);
        true
    }

    /// Read a command (consumer side - audio thread)
    pub fn read(&self) -> Option<AudioCommand> {
        let rp = self.read_pos.load(Ordering::Relaxed);
        let wp = self.write_pos.load(Ordering::Acquire);

        if rp == wp {
            return None; // empty
        }

        let cmd = unsafe {
            let ptr = self.buffer.as_ptr();
            ptr.add(rp).read()
        };

        self.read_pos.store((rp + 1) % RING_SIZE, Ordering::Release);
        Some(cmd)
    }
}

// Safety: RingBuffer is designed for single-producer single-consumer.
// The atomic operations ensure memory ordering.
unsafe impl Send for RingBuffer {}
unsafe impl Sync for RingBuffer {}
