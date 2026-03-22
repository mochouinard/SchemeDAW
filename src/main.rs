mod audio;
mod dsp;
mod sequencer;
mod project;
mod gui;

use std::sync::Arc;
use std::time::Instant;

use iced::widget::{button, column, container, row, scrollable, slider, text, Rule};
use iced::{Element, Length, Subscription, Theme, Color};
use iced::time;

use audio::command::{AudioCommand, CmdType, RingBuffer};
use audio::engine::AudioEngine;
use audio::preset::PRESET_NAMES;
use sequencer::{PatternBank, Arrangement, GRID_ROWS, GRID_COLS, MAX_PATTERNS, MAX_ARRANGEMENT};
use project::Project;

const TRACK_LABELS: [&str; 8] = ["Lead", "Bass", "Pluck", "Pad", "Kick", "Snare", "HH-C", "HH-O"];
const DEFAULT_PRESETS: [usize; 8] = [0, 13, 11, 3, 6, 7, 8, 9];
const DEFAULT_NOTES: [u8; 8] = [48, 51, 55, 60, 36, 38, 42, 46];

// Preset options per track row
const MELODIC_PRESETS: [[usize; 4]; 4] = [
    [0, 15, 11, 12],  // lead
    [13, 1, 2, 14],   // bass
    [11, 4, 5, 12],   // pluck
    [3, 14, 5, 4],    // pad
];
const DRUM_PRESETS: [[usize; 4]; 4] = [
    [6, 1, 2, 13],    // kick
    [7, 10, 12, 11],  // snare
    [8, 9, 10, 4],    // hh-c
    [9, 8, 4, 5],     // hh-o
];

fn main() -> iced::Result {
    env_logger::init();

    // Create shared ring buffer
    let ring = Arc::new(RingBuffer::new());
    let ring_audio = ring.clone();

    // Start audio thread
    std::thread::spawn(move || {
        run_audio_thread(ring_audio);
    });

    // Start Iced GUI
    iced::application("Audio DAC", DawApp::update, DawApp::view)
        .subscription(DawApp::subscription)
        .theme(|_| Theme::Dark)
        .window_size((1400.0, 900.0))
        .run_with(move || {
            let app = DawApp::new(ring.clone());
            (app, iced::Task::none())
        })
}

fn run_audio_thread(ring: Arc<RingBuffer>) {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

    let host = cpal::default_host();
    let device = match host.default_output_device() {
        Some(d) => d,
        None => {
            eprintln!("No audio output device found!");
            return;
        }
    };

    let config = cpal::StreamConfig {
        channels: 2,
        sample_rate: cpal::SampleRate(44100),
        buffer_size: cpal::BufferSize::Fixed(512),
    };

    let sample_rate = config.sample_rate.0 as f32;
    let mut engine = AudioEngine::new(sample_rate);

    // Load default presets
    for (i, &preset) in DEFAULT_PRESETS.iter().enumerate() {
        audio::preset::load_preset(&mut engine.tracks[i], preset);
    }

    let stream = device.build_output_stream(
        &config,
        move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
            engine.process_commands(&ring);
            engine.render(data);
        },
        |err| eprintln!("Audio stream error: {}", err),
        None,
    );

    match stream {
        Ok(s) => {
            s.play().unwrap_or_else(|e| eprintln!("Failed to play: {}", e));
            eprintln!("Audio started: 44100 Hz, 2 channels");
            // Keep thread alive
            loop { std::thread::sleep(std::time::Duration::from_secs(60)); }
        }
        Err(e) => {
            eprintln!("Failed to build audio stream: {}", e);
            eprintln!("GUI will run without audio.");
        }
    }
}

// ---- Messages ----

#[derive(Debug, Clone)]
enum Message {
    // Transport
    TogglePlay,
    SetBpm(f32),
    Tick(Instant),

    // Sequencer
    CellClicked(usize, usize),
    SelectPattern(usize),
    NextPattern,
    PrevPattern,
    ClearPattern,
    CopyPattern,
    AddPattern,

    // Arrangement
    ToggleSongMode,
    ArrangementSlotClick(usize),
    ArrangementLenUp,
    ArrangementLenDown,

    // Track
    SetVolume(usize, f32),
    ToggleMute(usize),
    ToggleSolo(usize),
    SetPreset(usize, usize),
    NoteUp(usize),
    NoteDown(usize),
    OctaveUp(usize),
    OctaveDown(usize),

    // Global
    SetMasterVolume(f32),
    SetCutoff(f32),
    SetResonance(f32),

    // File
    Save,
    Load,
}

// ---- Application ----

struct DawApp {
    ring: Arc<RingBuffer>,

    // Transport
    bpm: f32,
    playing: bool,
    current_step: usize,
    last_step_time: Instant,

    // Patterns
    pattern_bank: PatternBank,
    current_pattern: usize,

    // Arrangement
    arrangement: Arrangement,
    arrangement_mode: bool,
    arrangement_pos: usize,

    // Track state
    track_presets: [usize; 8],
    track_volumes: [f32; 8],
    track_mutes: [bool; 8],
    track_solos: [bool; 8],
    track_notes: [u8; 8],

    // Global
    master_volume: f32,
    global_cutoff: f32,
    global_resonance: f32,

    // Status
    status: String,
}

impl DawApp {
    fn new(ring: Arc<RingBuffer>) -> Self {
        // Send initial presets
        for (i, &preset) in DEFAULT_PRESETS.iter().enumerate() {
            ring.write(AudioCommand::new(CmdType::LoadPreset, i as u8, preset as u8, 0, 0.0));
        }

        Self {
            ring,
            bpm: 120.0,
            playing: false,
            current_step: 0,
            last_step_time: Instant::now(),
            pattern_bank: PatternBank::new(),
            current_pattern: 0,
            arrangement: Arrangement::new(),
            arrangement_mode: false,
            arrangement_pos: 0,
            track_presets: DEFAULT_PRESETS,
            track_volumes: [0.8; 8],
            track_mutes: [false; 8],
            track_solos: [false; 8],
            track_notes: DEFAULT_NOTES,
            master_volume: 0.8,
            global_cutoff: 4000.0,
            global_resonance: 0.3,
            status: "Ready".into(),
        }
    }

    fn send(&self, cmd: CmdType, track: u8, p1: u8, p2: u8, fval: f32) {
        self.ring.write(AudioCommand::new(cmd, track, p1, p2, fval));
    }

    fn subscription(&self) -> Subscription<Message> {
        // Tick every 1ms for sequencer timing
        time::every(std::time::Duration::from_millis(1)).map(|_| Message::Tick(Instant::now()))
    }

    fn update(&mut self, message: Message) -> iced::Task<Message> {
        match message {
            Message::TogglePlay => {
                self.playing = !self.playing;
                if self.playing {
                    self.last_step_time = Instant::now();
                    self.current_step = 0;
                    if self.arrangement_mode { self.arrangement_pos = 0; }
                } else {
                    for i in 0..8 {
                        self.send(CmdType::AllNotesOff, i as u8, 0, 0, 0.0);
                    }
                    self.current_step = 0;
                }
            }

            Message::SetBpm(v) => { self.bpm = v; }

            Message::Tick(_now) => {
                if self.playing {
                    let step_ms = (60000.0 / (self.bpm * 4.0)) as u128;
                    let elapsed = self.last_step_time.elapsed().as_millis();

                    if elapsed >= step_ms {
                        // Get active pattern
                        let pat_idx = if self.arrangement_mode {
                            self.arrangement.slots[self.arrangement_pos]
                        } else {
                            self.current_pattern
                        };
                        let pat = &self.pattern_bank.patterns[pat_idx];

                        // Note off previous step
                        for r in 0..GRID_ROWS {
                            let prev_note = pat.get(r, self.current_step);
                            if prev_note > 0 {
                                self.send(CmdType::NoteOff, r as u8, prev_note, 0, 0.0);
                            }
                        }

                        // Advance
                        self.current_step = (self.current_step + 1) % GRID_COLS;

                        // Pattern boundary -> arrangement advance
                        if self.current_step == 0 && self.arrangement_mode {
                            self.arrangement_pos = (self.arrangement_pos + 1) % self.arrangement.length;
                        }

                        // Note on new step
                        let pat_idx = if self.arrangement_mode {
                            self.arrangement.slots[self.arrangement_pos]
                        } else {
                            self.current_pattern
                        };
                        let pat = &self.pattern_bank.patterns[pat_idx];

                        for r in 0..GRID_ROWS {
                            let note = pat.get(r, self.current_step);
                            if note > 0 {
                                self.send(CmdType::NoteOn, r as u8, note, 100, 0.0);
                            }
                        }

                        self.last_step_time = Instant::now();
                    }
                }
            }

            Message::CellClicked(row, col) => {
                let pat = &mut self.pattern_bank.patterns[self.current_pattern];
                let current = pat.get(row, col);
                if current > 0 {
                    pat.set(row, col, 0);
                } else {
                    pat.set(row, col, self.track_notes[row]);
                }
            }

            Message::SelectPattern(i) => { self.current_pattern = i; }
            Message::NextPattern => {
                if self.current_pattern < self.pattern_bank.num_active - 1 {
                    self.current_pattern += 1;
                }
            }
            Message::PrevPattern => {
                if self.current_pattern > 0 { self.current_pattern -= 1; }
            }
            Message::ClearPattern => {
                self.pattern_bank.patterns[self.current_pattern].clear();
            }
            Message::CopyPattern => {
                if self.current_pattern < self.pattern_bank.num_active - 1 {
                    let src = self.pattern_bank.patterns[self.current_pattern].clone();
                    self.pattern_bank.patterns[self.current_pattern + 1].copy_from(&src);
                }
            }
            Message::AddPattern => {
                if self.pattern_bank.num_active < MAX_PATTERNS {
                    self.pattern_bank.num_active += 1;
                }
            }

            Message::ToggleSongMode => { self.arrangement_mode = !self.arrangement_mode; }
            Message::ArrangementSlotClick(i) => {
                let current = self.arrangement.slots[i];
                self.arrangement.slots[i] = (current + 1) % self.pattern_bank.num_active;
            }
            Message::ArrangementLenUp => {
                if self.arrangement.length < MAX_ARRANGEMENT {
                    self.arrangement.length += 1;
                }
            }
            Message::ArrangementLenDown => {
                if self.arrangement.length > 1 {
                    self.arrangement.length -= 1;
                }
            }

            Message::SetVolume(i, v) => {
                self.track_volumes[i] = v;
                self.send(CmdType::SetVolume, i as u8, 0, 0, v);
            }
            Message::ToggleMute(i) => {
                self.track_mutes[i] = !self.track_mutes[i];
                self.send(CmdType::MuteTrack, i as u8, self.track_mutes[i] as u8, 0, 0.0);
            }
            Message::ToggleSolo(i) => {
                self.track_solos[i] = !self.track_solos[i];
                self.send(CmdType::SoloTrack, i as u8, self.track_solos[i] as u8, 0, 0.0);
            }
            Message::SetPreset(track, preset) => {
                self.track_presets[track] = preset;
                self.send(CmdType::LoadPreset, track as u8, preset as u8, 0, 0.0);
            }
            Message::NoteUp(i) => {
                if self.track_notes[i] < 127 { self.track_notes[i] += 1; }
            }
            Message::NoteDown(i) => {
                if self.track_notes[i] > 0 { self.track_notes[i] -= 1; }
            }
            Message::OctaveUp(i) => {
                if self.track_notes[i] <= 115 { self.track_notes[i] += 12; }
            }
            Message::OctaveDown(i) => {
                if self.track_notes[i] >= 12 { self.track_notes[i] -= 12; }
            }

            Message::SetMasterVolume(v) => {
                self.master_volume = v;
                self.send(CmdType::MasterVolume, 0, 0, 0, v);
            }
            Message::SetCutoff(v) => {
                self.global_cutoff = v;
                for t in 0..8 {
                    self.send(CmdType::SetFilter, t as u8, 0, 0, v);
                }
            }
            Message::SetResonance(v) => {
                self.global_resonance = v;
                for t in 0..8 {
                    self.send(CmdType::SetFilter, t as u8, 1, 0, v);
                }
            }

            Message::Save => {
                let proj = Project {
                    version: 2,
                    bpm: self.bpm,
                    master_volume: self.master_volume,
                    track_presets: self.track_presets.to_vec(),
                    track_volumes: self.track_volumes.to_vec(),
                    track_notes: self.track_notes.to_vec(),
                    track_mutes: self.track_mutes.to_vec(),
                    track_solos: self.track_solos.to_vec(),
                    pattern_bank: self.pattern_bank.clone(),
                    arrangement: self.arrangement.clone(),
                };
                match proj.save("project.json") {
                    Ok(_) => self.status = "Project saved".into(),
                    Err(e) => self.status = format!("Save failed: {}", e),
                }
            }
            Message::Load => {
                match Project::load("project.json") {
                    Ok(proj) => {
                        self.bpm = proj.bpm;
                        self.master_volume = proj.master_volume;
                        self.pattern_bank = proj.pattern_bank;
                        self.arrangement = proj.arrangement;
                        for i in 0..8.min(proj.track_presets.len()) {
                            self.track_presets[i] = proj.track_presets[i];
                            self.send(CmdType::LoadPreset, i as u8, proj.track_presets[i] as u8, 0, 0.0);
                        }
                        for i in 0..8.min(proj.track_volumes.len()) {
                            self.track_volumes[i] = proj.track_volumes[i];
                            self.send(CmdType::SetVolume, i as u8, 0, 0, proj.track_volumes[i]);
                        }
                        for i in 0..8.min(proj.track_notes.len()) {
                            self.track_notes[i] = proj.track_notes[i];
                        }
                        self.send(CmdType::MasterVolume, 0, 0, 0, self.master_volume);
                        self.status = "Project loaded".into();
                    }
                    Err(e) => self.status = format!("Load failed: {}", e),
                }
            }
        }

        iced::Task::none()
    }

    fn view(&self) -> Element<Message> {
        let toolbar = self.view_toolbar();
        let sequencer = self.view_sequencer();
        let sounds = self.view_sounds();
        let arrangement_panel = self.view_arrangement();
        let mixer = self.view_mixer();

        let main_area = row![
            sequencer,
            sounds,
        ].spacing(2);

        column![
            toolbar,
            main_area,
            arrangement_panel,
            mixer,
        ]
        .spacing(2)
        .padding(4)
        .into()
    }

    // ---- Panel view methods ----

    fn view_toolbar(&self) -> Element<Message> {
        row![
            button("Save").on_press(Message::Save).padding(6),
            button("Load").on_press(Message::Load).padding(6),
            text(" | ").size(14),
            button(if self.playing { "Stop" } else { "Play" })
                .on_press(Message::TogglePlay).padding(6),
            text(format!(" BPM: {:.0} ", self.bpm)).size(14),
            slider(40.0..=300.0, self.bpm, Message::SetBpm).width(120),
            text(if self.playing {
                format!(" PLAYING Step {}/16", self.current_step + 1)
            } else {
                " STOPPED".into()
            }).size(14).color(if self.playing {
                Color::from_rgb(0.2, 0.8, 0.3)
            } else {
                Color::from_rgb(0.5, 0.5, 0.5)
            }),
            text(" | ").size(14),
            button("<").on_press(Message::PrevPattern).padding(4),
            text(format!(" Pat {} ", self.current_pattern + 1)).size(14),
            button(">").on_press(Message::NextPattern).padding(4),
            button(if self.arrangement_mode { "Song" } else { "Loop" })
                .on_press(Message::ToggleSongMode).padding(6),
            text(format!(" {} ", &self.status)).size(12)
                .color(Color::from_rgb(0.5, 0.7, 0.5)),
        ]
        .spacing(4)
        .padding(6)
        .into()
    }

    fn view_sequencer(&self) -> Element<Message> {
        let pat = &self.pattern_bank.patterns[self.current_pattern];

        let mut grid_col = column![
            text(format!("Pattern {}", self.current_pattern + 1))
                .size(13)
                .color(gui::theme::ACCENT),
        ].spacing(1);

        for r in 0..GRID_ROWS {
            let label_color = if r < 4 { gui::theme::MELODIC } else { gui::theme::DRUM };
            let mut cells = row![
                text(TRACK_LABELS[r]).size(11).width(55).color(label_color),
            ].spacing(1);

            for c in 0..GRID_COLS {
                let note = pat.get(r, c);
                let is_playing = self.playing && c == self.current_step;
                let is_active = note > 0;

                let label = if is_active {
                    dsp::midi_to_name(note)
                } else {
                    String::new()
                };

                let bg = if is_playing && is_active {
                    gui::theme::CELL_PLAYING
                } else if is_playing {
                    Color::from_rgb(0.27, 0.27, 0.18)
                } else if is_active {
                    if r < 4 { gui::theme::CELL_ACTIVE_MELODIC } else { gui::theme::CELL_ACTIVE_DRUM }
                } else if c % 4 == 0 {
                    gui::theme::CELL_BEAT
                } else {
                    gui::theme::CELL_EMPTY
                };

                cells = cells.push(
                    button(text(label).size(9).center())
                        .on_press(Message::CellClicked(r, c))
                        .padding(2)
                        .width(38)
                        .height(26)
                        .style(move |_theme, _status| button::Style {
                            background: Some(iced::Background::Color(bg)),
                            text_color: Color::WHITE,
                            border: iced::Border {
                                color: Color::from_rgb(0.22, 0.22, 0.24),
                                width: 1.0,
                                radius: 2.0.into(),
                            },
                            ..Default::default()
                        })
                );
            }
            grid_col = grid_col.push(cells);
        }

        // Pattern management
        let pat_mgmt = row![
            button("Clear").on_press(Message::ClearPattern).padding(4),
            button("Copy ->").on_press(Message::CopyPattern).padding(4),
            button("+Pat").on_press(Message::AddPattern).padding(4),
            text(format!("{} patterns", self.pattern_bank.num_active)).size(12),
        ].spacing(4);

        container(column![grid_col, pat_mgmt].spacing(4))
            .width(Length::FillPortion(6))
            .padding(6)
            .into()
    }

    fn view_sounds(&self) -> Element<Message> {
        let mut col = column![].spacing(2);

        for r in 0..GRID_ROWS {
            let label_color = if r < 4 { gui::theme::MELODIC } else { gui::theme::DRUM };

            // Track header + note controls
            let header = row![
                text(format!("{}. {}", r + 1, TRACK_LABELS[r]))
                    .size(11).width(70).color(label_color),
                text(dsp::midi_to_name(self.track_notes[r])).size(11).width(35)
                    .color(Color::from_rgb(0.8, 0.9, 0.6)),
                button("-Oct").on_press(Message::OctaveDown(r)).padding(2),
                button("-").on_press(Message::NoteDown(r)).padding(2),
                button("+").on_press(Message::NoteUp(r)).padding(2),
                button("+Oct").on_press(Message::OctaveUp(r)).padding(2),
            ].spacing(2);

            // Preset buttons
            let presets_for_row = if r < 4 { &MELODIC_PRESETS[r] } else { &DRUM_PRESETS[r - 4] };
            let mut preset_row = row![].spacing(2);
            for &pi in presets_for_row {
                let is_active = self.track_presets[r] == pi;
                let label = if is_active {
                    format!(">{}", PRESET_NAMES[pi])
                } else {
                    PRESET_NAMES[pi].to_string()
                };
                preset_row = preset_row.push(
                    button(text(label).size(9))
                        .on_press(Message::SetPreset(r, pi))
                        .padding(3)
                );
            }

            col = col.push(header);
            col = col.push(preset_row);
        }

        // Global controls
        col = col.push(Rule::horizontal(1));
        col = col.push(text("Filter").size(12).color(gui::theme::ACCENT));
        col = col.push(row![
            text("Cut").size(10).width(30),
            slider(20.0..=20000.0, self.global_cutoff, Message::SetCutoff).width(Length::Fill),
        ].spacing(4));
        col = col.push(row![
            text("Res").size(10).width(30),
            slider(0.0..=0.95, self.global_resonance, Message::SetResonance).width(Length::Fill),
        ].spacing(4));

        col = col.push(Rule::horizontal(1));
        col = col.push(text("Master").size(12).color(gui::theme::ACCENT));
        col = col.push(row![
            text("Vol").size(10).width(30),
            slider(0.0..=1.0, self.master_volume, Message::SetMasterVolume).width(Length::Fill),
            text(format!("{}%", (self.master_volume * 100.0) as i32)).size(10),
        ].spacing(4));

        container(scrollable(col.padding(6)))
            .width(Length::FillPortion(4))
            .into()
    }

    fn view_arrangement(&self) -> Element<Message> {
        let mode_label = if self.arrangement_mode { "SONG MODE" } else { "LOOP MODE" };
        let header = row![
            text(format!("Arrangement ({} bars) [{}]", self.arrangement.length, mode_label))
                .size(12).color(gui::theme::ACCENT),
        ];

        let mut slots = row![].spacing(2);
        for i in 0..self.arrangement.length.min(16) {
            let pat_idx = self.arrangement.slots[i];
            let is_playing = self.playing && self.arrangement_mode && i == self.arrangement_pos;

            let bg = if is_playing {
                gui::theme::CELL_PLAYING
            } else {
                gui::theme::BG_HEADER
            };

            slots = slots.push(
                button(text(format!("P{}", pat_idx + 1)).size(10).center())
                    .on_press(Message::ArrangementSlotClick(i))
                    .padding(4)
                    .width(44)
                    .style(move |_theme, _status| button::Style {
                        background: Some(iced::Background::Color(bg)),
                        text_color: Color::WHITE,
                        border: iced::Border {
                            color: gui::theme::BORDER,
                            width: 1.0,
                            radius: 2.0.into(),
                        },
                        ..Default::default()
                    })
            );
        }

        let len_controls = row![
            text("Len:").size(11),
            button("-").on_press(Message::ArrangementLenDown).padding(2),
            button("+").on_press(Message::ArrangementLenUp).padding(2),
        ].spacing(4);

        container(column![header, slots, len_controls].spacing(2).padding(6))
            .width(Length::Fill)
            .into()
    }

    fn view_mixer(&self) -> Element<Message> {
        let mut col = column![
            text("Mixer").size(12).color(gui::theme::ACCENT),
        ].spacing(1);

        for i in 0..8 {
            let label_color = if i < 4 { gui::theme::MELODIC } else { gui::theme::DRUM };

            let mute_label = if self.track_mutes[i] { "M!" } else { "M" };
            let solo_label = if self.track_solos[i] { "S!" } else { "S" };

            let track_row = row![
                button(mute_label).on_press(Message::ToggleMute(i)).padding(3).width(32),
                button(solo_label).on_press(Message::ToggleSolo(i)).padding(3).width(32),
                text(format!("{}. {} - {}",
                    i + 1, TRACK_LABELS[i], PRESET_NAMES[self.track_presets[i]]))
                    .size(11).width(200).color(label_color),
                slider(0.0..=1.0, self.track_volumes[i], move |v| Message::SetVolume(i, v))
                    .width(Length::Fill),
                text(format!("{}%", (self.track_volumes[i] * 100.0) as i32))
                    .size(10).width(35),
            ].spacing(4).align_y(iced::Alignment::Center);

            col = col.push(track_row);
        }

        container(col.padding(6))
            .width(Length::Fill)
            .into()
    }
}
