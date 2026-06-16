//! mxm4-hapticd — MX Master 4 haptic daemon.
//!
//! Sole owner of the Bolt receiver's HID++ session. Discovers the mouse
//! and its HAPTIC feature index natively over HID (no Solaar CLI, no
//! on-disk cache — device state lives only in memory), serializes haptic
//! playback with debounce + per-pulse pacing, and re-discovers when the
//! mouse disconnects/reconnects (possibly at a different receiver slot).
//!
//! Inputs: waveform names on the IPC endpoint (AF_UNIX socket on Unix, Win32
//! named pipe on Windows; see lib::IpcServer) from the thin client (Solaar
//! rules) and the notification bridge. Output: HID++ play reports.
//!
//! Concurrency — a SINGLE I/O-owner thread holds the one `hidapi::HidDevice`
//! (that type is `Send` but not `Sync`, and macOS IOKit does not promise that
//! a second handle sees the same unsolicited reports the way Linux hidraw
//! broadcasts to every open fd):
//!
//! - main thread: owns the HidDevice; a short read_timeout() poll loop drains
//!   input reports (0x41 reconnect notifications, Root.GetFeature replies during
//!   discovery) and services play/discovery requests between reads.
//! - accept thread: the IpcServer accept loop; forwards waveform ids to the
//!   I/O thread over an mpsc channel.
//!
//! Discovery (verified against Solaar receiver.py / libratbag hidpp20.c):
//!   enable 0x41 notifications (reg 0x00) -> re-announce (reg 0x02) to seed
//!   which slots are connected -> Root.GetFeature(0x19B0) on each connected
//!   slot; the slot that returns a feature index (not ERR_INVALID_FEATURE_
//!   INDEX) IS the MX Master 4, and the returned index is its HAPTIC index.
//!   Per-slot GetFeature is NOT used as a presence probe (a sleeping slot
//!   would block the full 4 s device timeout), so only connected slots are
//!   probed. Spontaneous 0x41s thereafter drive reconnect re-discovery.
//!
//! Linux (hidraw backend) + macOS (IOKit, shared open) + Windows (native HID +
//! named-pipe IPC). See crates/README.md.

use std::process::ExitCode;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

use hidapi::{HidApi, HidDevice};
use mxm4_haptic as lib;

/// Pacing: minimum gap held AFTER a pulse so the motor finishes the
/// waveform before the next fires (the firmware exposes no "playback
/// done" event, so this is a duration estimate, tunable via env).
fn pacing_ms() -> u64 {
    std::env::var("MXM4D_PACING_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(180)
}
/// Debounce: pulses arriving within this of the last one are dropped.
fn debounce_ms() -> u64 {
    std::env::var("MXM4D_DEBOUNCE_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(120)
}
/// Read poll quantum. The single I/O thread blocks in read_timeout() for at
/// most this long, so it also bounds how late a queued play command is
/// noticed — kept small (8 ms ≈ imperceptible vs the 180 ms pacing) so
/// button-hold haptics still feel immediate.
fn poll_ms() -> i32 {
    std::env::var("MXM4D_POLL_MS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8)
}

#[derive(Clone, Copy)]
struct Target {
    dev_idx: u8,
    haptic_idx: u8,
}

/// Send Root.GetFeature(0x19B0) to `dev` and read replies (≤4 s) until the
/// HAPTIC feature index arrives. Returns None on a HID++ error reply (slot is
/// not the MX Master 4) or timeout. 0x41 notifications seen meanwhile keep
/// `connected` fresh.
fn get_haptic_index(device: &HidDevice, dev: u8, connected: &mut [bool; 7]) -> Option<u8> {
    let req = lib::build_get_feature(
        dev,
        lib::HAPTIC_FEATURE_HI,
        lib::HAPTIC_FEATURE_LO,
        lib::SW_ID,
    );
    if device.write(&req).is_err() {
        return None;
    }
    let deadline = Instant::now() + Duration::from_secs(4);
    let mut buf = [0u8; 64];
    while let Some(remaining) = remaining_ms(deadline) {
        match device.read_timeout(&mut buf, remaining) {
            Ok(0) => {}
            Ok(n) => {
                let report = &buf[..n];
                if let Some((d, established)) = lib::parse_connection_notification(report) {
                    if (d as usize) < connected.len() {
                        connected[d as usize] = established;
                    }
                    continue;
                }
                match lib::classify_root_reply(report, dev, lib::SW_ID) {
                    lib::RootReply::FeatureIndex(idx) => return Some(idx),
                    lib::RootReply::Hidpp20Error(_) | lib::RootReply::Hidpp10Error(_) => {
                        return None
                    }
                    lib::RootReply::NotForUs => continue,
                }
            }
            Err(_) => return None,
        }
    }
    None
}

/// Re-announce connected devices, drain the 0x41 burst for ~600 ms to seed the
/// connected-slot set, then probe each connected slot for HAPTIC. First hit
/// wins.
fn discover(device: &HidDevice, connected: &mut [bool; 7]) -> Option<Target> {
    let _ = device.write(&lib::REANNOUNCE_DEVICES);
    let deadline = Instant::now() + Duration::from_millis(600);
    let mut buf = [0u8; 64];
    while let Some(remaining) = remaining_ms(deadline) {
        match device.read_timeout(&mut buf, remaining) {
            Ok(0) => {}
            Ok(n) => {
                if let Some((dev, established)) = lib::parse_connection_notification(&buf[..n]) {
                    if (dev as usize) < connected.len() {
                        connected[dev as usize] = established;
                    }
                }
            }
            Err(_) => return None,
        }
    }

    let slots: Vec<u8> = (1u8..=6).filter(|d| connected[*d as usize]).collect();
    for dev in slots {
        if let Some(haptic_idx) = get_haptic_index(device, dev, connected) {
            eprintln!("mxm4-hapticd: MX Master 4 at slot {dev}, HAPTIC index {haptic_idx}");
            return Some(Target {
                dev_idx: dev,
                haptic_idx,
            });
        }
    }
    None
}

/// Milliseconds left until `deadline`, or None once it has passed. Clamped to
/// i32 for hidapi's read_timeout argument.
fn remaining_ms(deadline: Instant) -> Option<i32> {
    let now = Instant::now();
    if now >= deadline {
        return None;
    }
    Some((deadline - now).as_millis().min(i32::MAX as u128) as i32)
}

/// State threaded through one play request.
struct PlayState<'a> {
    connected: &'a mut [bool; 7],
    target: &'a mut Option<Target>,
    dirty: &'a mut bool,
    last_play: &'a mut Instant,
    last_discover: &'a mut Instant,
    debounce: Duration,
    pacing: Duration,
}

/// Debounce, (re)discover if needed, write the play report, record timing.
fn handle_play(wf_id: u8, device: &HidDevice, st: &mut PlayState) {
    // The motor-settle gap (pacing) and input coalescing (debounce) collapse
    // to a single min-gap in the single-threaded loop; honor the larger so
    // either knob still works.
    let gap = st.last_play.elapsed();
    if gap < st.debounce || gap < st.pacing {
        return;
    }

    if st.target.is_none() || *st.dirty {
        // Rate-limit failed discovery so an absent device doesn't make every
        // queued command pay the 600 ms re-announce wait.
        if st.target.is_none() || st.last_discover.elapsed() > Duration::from_secs(3) {
            *st.last_discover = Instant::now();
            *st.target = discover(device, st.connected);
            *st.dirty = false;
        }
    }

    let Some(t) = *st.target else {
        return; // device absent; a future 0x41 will set dirty + re-discover
    };

    let pkt = lib::build_play_packet(t.dev_idx, t.haptic_idx, wf_id);
    if device.write(&pkt).is_err() {
        // Write failed mid-session: drop the target so the next command
        // re-discovers. A persistently dead handle surfaces as a read error.
        *st.target = None;
        return;
    }
    *st.last_play = Instant::now();
}

fn drain_latest(rx: &Receiver<u8>) -> Result<Option<u8>, TryRecvError> {
    let mut latest = None;
    loop {
        match rx.try_recv() {
            Ok(wf_id) => latest = Some(wf_id),
            Err(TryRecvError::Empty) => return Ok(latest),
            Err(TryRecvError::Disconnected) => return Err(TryRecvError::Disconnected),
        }
    }
}

/// The single I/O-owner loop. Polls the device for input reports, processes
/// 0x41 reconnect notifications, and services queued play commands between
/// reads. Never returns: exits the process on a read error (receiver
/// unplugged) so systemd restarts us against a freshly enumerated node.
fn io_loop(device: HidDevice, rx: Receiver<u8>) -> ! {
    let debounce = Duration::from_millis(debounce_ms());
    let pacing = Duration::from_millis(pacing_ms());
    let poll = poll_ms();

    // Enable 0x41 notifications and seed the connected-slot set. Both are
    // idempotent receiver-register writes (safe alongside a running Solaar).
    let _ = device.write(&lib::ENABLE_NOTIFICATIONS);
    let _ = device.write(&lib::REANNOUNCE_DEVICES);

    let mut connected = [false; 7];
    let mut target: Option<Target> = None;
    let mut dirty = false;
    let mut last_play = Instant::now() - Duration::from_secs(3600);
    let mut last_discover = Instant::now() - Duration::from_secs(3600);
    let mut buf = [0u8; 64];

    loop {
        // Always drain reads (the hidapi macOS input queue is finite), routing
        // reconnect notifications even when no command is pending.
        match device.read_timeout(&mut buf, poll) {
            Ok(0) => {}
            Ok(n) => {
                if let Some((dev, established)) = lib::parse_connection_notification(&buf[..n]) {
                    if (dev as usize) < connected.len() {
                        connected[dev as usize] = established;
                    }
                    if let Some(t) = target {
                        if t.dev_idx == dev && !established {
                            target = None;
                        }
                    }
                    dirty = true;
                }
            }
            Err(e) => {
                eprintln!("mxm4-hapticd: HID read error ({e}); exiting for restart");
                std::process::exit(1);
            }
        }

        match drain_latest(&rx) {
            Ok(Some(wf_id)) => {
                let mut st = PlayState {
                    connected: &mut connected,
                    target: &mut target,
                    dirty: &mut dirty,
                    last_play: &mut last_play,
                    last_discover: &mut last_discover,
                    debounce,
                    pacing,
                };
                handle_play(wf_id, &device, &mut st);
            }
            Ok(None) => {}
            Err(TryRecvError::Empty) => unreachable!("drain_latest converts Empty to Ok(None)"),
            Err(TryRecvError::Disconnected) => std::process::exit(0),
        }
    }
}

/// Enumerate the Bolt receiver's HID++ control interface and open it,
/// retrying until the receiver is present (e.g. daemon started before the
/// dongle is plugged, or just restarted). The `HidApi` context is kept alive
/// by the caller for the device's lifetime.
fn open_hidpp(api: &mut HidApi) -> HidDevice {
    loop {
        let path = api
            .device_list()
            .find(|d| {
                d.vendor_id() == lib::BOLT_VID
                    && d.product_id() == lib::BOLT_PID
                    && (d.interface_number() == lib::HIDPP_INTERFACE
                        || d.usage_page() == lib::HIDPP_USAGE_PAGE)
            })
            .map(|d| d.path().to_owned());

        if let Some(path) = path {
            match api.open_path(&path) {
                Ok(device) => {
                    eprintln!("mxm4-hapticd: opened {}", path.to_string_lossy());
                    return device;
                }
                Err(e) => {
                    eprintln!(
                        "mxm4-hapticd: open {} failed ({e}); retrying",
                        path.to_string_lossy()
                    )
                }
            }
        }
        thread::sleep(Duration::from_secs(2));
        let _ = api.refresh_devices();
    }
}

fn main() -> ExitCode {
    // The accept loop runs on its own thread so the main thread can own the
    // device. IpcServer::bind is the AF_UNIX socket (Unix) or named pipe
    // (Windows); both yield one waveform name per accepted client.
    let server = match lib::IpcServer::bind() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("mxm4-hapticd: IPC bind failed ({e})");
            return ExitCode::from(1);
        }
    };
    eprintln!("mxm4-hapticd: listening on {}", server.endpoint());

    let (tx, rx) = mpsc::channel::<u8>();
    thread::spawn(move || loop {
        match server.next_name() {
            Ok(Some(name)) => {
                if let Some(wf_id) = lib::waveform_id(&name) {
                    let _ = tx.send(wf_id);
                }
            }
            Ok(None) => {}
            Err(e) => {
                eprintln!("mxm4-hapticd: accept error ({e})");
                // Avoid a hot error loop if the endpoint is persistently broken.
                thread::sleep(Duration::from_millis(200));
            }
        }
    });

    let mut api = match HidApi::new() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("mxm4-hapticd: hidapi init failed ({e})");
            return ExitCode::from(1);
        }
    };
    let device = open_hidpp(&mut api);
    io_loop(device, rx);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drain_latest_returns_newest_queued_waveform() {
        let (tx, rx) = mpsc::channel();
        tx.send(2).unwrap();
        tx.send(7).unwrap();
        tx.send(14).unwrap();

        assert_eq!(drain_latest(&rx), Ok(Some(14)));
        assert_eq!(drain_latest(&rx), Ok(None));
    }

    #[test]
    fn drain_latest_reports_disconnect_after_queue_is_empty() {
        let (tx, rx) = mpsc::channel();
        drop(tx);

        assert_eq!(drain_latest(&rx), Err(TryRecvError::Disconnected));
    }
}
