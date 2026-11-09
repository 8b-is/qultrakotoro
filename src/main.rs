//! kotorocli / qultrakotoro — the 100% Pure-Rust Zero-Float command-line face of qUltraKotoro.
//!
//! Offline-first on-device speech-to-text, QuantTern emotional ternary tagging (`qt:`),
//! soundscape noise profiling (`Silence | Quiet | Ambient | Noisy`), and 5-band LTC
//! Dynamic Environment Equalizer (`liquid-rust` +++ `wupz` +++ `qultrakotoro`).

use qultrakotoro::{
    decode_wav_i16, encode_vad_pq, resolve_local_kotoro_model, transcribe_wav_file,
    DynamicEqSnapshotPq, DynamicEqualizer, EmotionTagger, NoiseDetector, DEFAULT_THRESHOLD_PQ,
};
use std::env;
use std::fs;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream};
use std::path::Path;
use std::process::{Command, ExitCode};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const USAGE: &str = "\
kotorocli (qUltraKotoro v0.7.0) — 100% Pure-Rust Zero-Float on-device STT, QuantTern (qt:), NoiseDetector & 5-Band LTC EQ

USAGE
  kotorocli emotion <text...> [--json]
  kotorocli noise <audio-file> [--json]
  kotorocli eq <audio-file> [--json]
  kotorocli transcribe <audio-file> [--locale <tag>] [--json]
  kotorocli live [seconds] [--locale <tag>] [--json]
  kotorocli status [--json]
  kotorocli engines
  kotorocli locales

The QuantTern code packs a VAD emotion read (in exact p/q rationals) into {-1, 0, +1} trits (qt:xx).";

fn option_val<'a>(name: &str, args: &'a [String]) -> Option<&'a str> {
    let idx = args.iter().position(|a| a == name)?;
    args.get(idx + 1).map(String::as_str)
}

fn positional(args: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut skip = false;
    for a in args {
        if skip {
            skip = false;
            continue;
        }
        if a == "--locale" {
            skip = true;
            continue;
        }
        if a == "--json" {
            continue;
        }
        out.push(a.clone());
    }
    out
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 4);
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out
}

fn format_signed_centi(val_centi: i16) -> String {
    let sign = if val_centi >= 0 { '+' } else { '-' };
    let abs = val_centi.unsigned_abs();
    format!("{sign}{}.{:02}", abs / 100, abs % 100)
}

fn format_deci_db(val_deci: i32) -> String {
    let sign = if val_deci < 0 { "-" } else { "" };
    let abs = val_deci.unsigned_abs();
    format!("{sign}{}.{}", abs / 10, abs % 10)
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn main() -> ExitCode {
    let argv: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = argv.first().map(String::as_str) else {
        println!("{USAGE}");
        return ExitCode::SUCCESS;
    };
    let rest = &argv[1..];
    let json_out = argv.iter().any(|a| a == "--json");
    let locale = option_val("--locale", &argv).unwrap_or("en-US");

    match cmd {
        "help" | "-h" | "--help" => {
            println!("{USAGE}");
            ExitCode::SUCCESS
        }
        "--version" | "-V" | "version" => {
            println!("qultrakotoro (kotorocli) 0.7.0 — 100% Pure-Rust Zero-Float Sovereign STT + QuantTern");
            ExitCode::SUCCESS
        }
        "engines" => {
            let hot8785 = TcpStream::connect_timeout(
                &SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8785),
                Duration::from_millis(80),
            )
            .is_ok();
            let hot8786 = TcpStream::connect_timeout(
                &SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8786),
                Duration::from_millis(80),
            )
            .is_ok();
            let model = resolve_local_kotoro_model().unwrap_or("unavailable");
            println!(
                "qultrakotoro-hot\t127.0.0.1:8785 ({}) · ggml-large-v3-turbo-q5_0 · 0ms cold load · no cloud fallback",
                if hot8785 { "ONLINE" } else { "OFFLINE" }
            );
            println!(
                "liquid-rust\t\t127.0.0.1:8786 ({}) · Pure-Rust LFM2.5-Audio + Marine Salience",
                if hot8786 { "ONLINE" } else { "OFFLINE" }
            );
            println!("whisper-cli\t\t{model} · Direct local on-device fallback");
            ExitCode::SUCCESS
        }
        "locales" => {
            for l in ["en-US", "ja-JP", "zh-CN", "zh-TW", "nan-TW", "hu-HU", "auto"] {
                println!("{l}");
            }
            ExitCode::SUCCESS
        }
        "status" => {
            let hot8785 = TcpStream::connect_timeout(
                &SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8785),
                Duration::from_millis(80),
            )
            .is_ok();
            let hot8786 = TcpStream::connect_timeout(
                &SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8786),
                Duration::from_millis(80),
            )
            .is_ok();
            let model = resolve_local_kotoro_model().unwrap_or("none");
            if json_out {
                println!(
                    "{{\"ok\":true,\"engine\":\"qultrakotoro\",\"version\":\"0.7.0\",\"hot_8785\":{hot8785},\"liquid_rust_8786\":{hot8786},\"model\":\"{}\",\"zero_float_pq\":\"1/1\"}}",
                    json_escape(model)
                );
            } else {
                println!("qUltraKotoro v0.7.0 (100% Pure-Rust Zero-Float)");
                println!("  hot :8785 : {}", if hot8785 { "ONLINE" } else { "OFFLINE" });
                println!("  hot :8786 : {}", if hot8786 { "ONLINE" } else { "OFFLINE" });
                println!("  model     : {model}");
            }
            ExitCode::SUCCESS
        }
        "emotion" => {
            let text = positional(rest).join(" ");
            if text.trim().is_empty() {
                eprintln!("error: emotion: need some text");
                return ExitCode::from(1);
            }
            let vad = EmotionTagger::vad_pq(&text);
            let code = encode_vad_pq(vad, DEFAULT_THRESHOLD_PQ);
            if json_out {
                println!(
                    "{{ \"valence_pq\": \"{}\", \"arousal_pq\": \"{}\", \"dominance_pq\": \"{}\", \"code\": \"{}\", \"magnitude\": {} }}",
                    vad.valence,
                    vad.arousal,
                    vad.dominance,
                    code.hex,
                    code.magnitude()
                );
            } else {
                println!(
                    "vad   v {}  a {}  d {}",
                    vad.valence, vad.arousal, vad.dominance
                );
                println!("code  {}   magnitude {}/3", code.hex, code.magnitude());
            }
            ExitCode::SUCCESS
        }
        "noise" => {
            let pos = positional(rest);
            let Some(path) = pos.first() else {
                eprintln!("error: noise: need an audio file");
                return ExitCode::from(1);
            };
            let Ok(bytes) = fs::read(path) else {
                eprintln!("error: noise: no such file: {path}");
                return ExitCode::from(1);
            };
            let Some((_sr, pcm)) = decode_wav_i16(&bytes) else {
                eprintln!("error: noise: cannot decode 16-bit PCM WAV: {path}");
                return ExitCode::from(1);
            };
            let mut detector = NoiseDetector::default();
            let mut idx = 0;
            while idx < pcm.len() {
                let end = (idx + 4096).min(pcm.len());
                detector.ingest_i16(&pcm[idx..end]);
                idx = end;
            }
            let p = detector.profile;
            if json_out {
                println!(
                    "{{ \"level_dbfs_pq\": \"{}\", \"peak_dbfs_pq\": \"{}\", \"zcr_pq\": \"{}\", \"zcr_permille\": {}, \"classification\": \"{}\" }}",
                    p.level_dbfs_pq(),
                    p.peak_dbfs_pq(),
                    p.zcr_pq,
                    p.zcr_permille,
                    p.classification.label()
                );
            } else {
                println!(
                    "level  {} dBFS ({})",
                    format_deci_db(p.level_deci_dbfs),
                    p.level_dbfs_pq()
                );
                println!(
                    "peak   {} dBFS ({})",
                    format_deci_db(p.peak_deci_dbfs),
                    p.peak_dbfs_pq()
                );
                println!("zcr    {}/1000 ({})", p.zcr_permille, p.zcr_pq);
                println!("class  {}", p.classification.label());
            }
            ExitCode::SUCCESS
        }
        "eq" => {
            let pos = positional(rest);
            let Some(path) = pos.first() else {
                eprintln!("error: eq: need an audio file");
                return ExitCode::from(1);
            };
            let Ok(bytes) = fs::read(path) else {
                eprintln!("error: eq: no such file: {path}");
                return ExitCode::from(1);
            };
            let Some((sr, pcm)) = decode_wav_i16(&bytes) else {
                eprintln!("error: eq: cannot decode 16-bit PCM WAV: {path}");
                return ExitCode::from(1);
            };
            if pcm.is_empty() {
                eprintln!("error: eq: empty audio");
                return ExitCode::from(1);
            }
            let mut eq = DynamicEqualizer::new(true);
            let mut snap: Option<DynamicEqSnapshotPq> = None;
            let mut idx = 0;
            while idx < pcm.len() {
                let end = (idx + 4096).min(pcm.len());
                snap = Some(eq.ingest_i16(&pcm[idx..end], sr));
                idx = end;
            }
            let s = snap.unwrap();
            let fold_hex = format!("0x{:016x}", s.wupz_fold);
            if json_out {
                println!(
                    "{{ \"class\": \"{}\", \"level_dbfs_pq\": \"{}\", \"salience_pq\": \"{}\", \"f0_hz_pq\": \"{}\", \"code\": \"{}\", \"sub60Hz_centi_db\": {}, \"low250Hz_centi_db\": {}, \"mid1kHz_centi_db\": {}, \"highMid4kHz_centi_db\": {}, \"air12kHz_centi_db\": {}, \"leftJackVol_permille\": {}, \"rightAirPodsVol_permille\": {}, \"wupzFold\": \"{}\", \"wupzByteDiff\": {}, \"wupzPopcount\": {} }}",
                    s.noise.classification.label(),
                    s.noise.level_dbfs_pq(),
                    s.salience_pq,
                    s.estimated_f0_pq,
                    s.emotion.hex,
                    s.bands.sub_60hz,
                    s.bands.low_250hz,
                    s.bands.mid_1khz,
                    s.bands.high_mid_4khz,
                    s.bands.air_12khz,
                    s.split_ear.left_jack_vol_permille,
                    s.split_ear.right_airpods_right_permille,
                    fold_hex,
                    s.wupz_byte_diff,
                    s.wupz_popcount
                );
            } else {
                println!(
                    "room   {:<7}  level {} dBFS  zcr {}/1000",
                    s.noise.classification.label(),
                    format_deci_db(s.noise.level_deci_dbfs),
                    s.noise.zcr_permille
                );
                println!(
                    "marine salience {}/1000 ({})  f0 {} Hz  code {}",
                    s.salience_permille, s.salience_pq, s.estimated_f0_pq, s.emotion.hex
                );
                println!(
                    "eq     60Hz {}dB | 250Hz {}dB | 1kHz {}dB | 4kHz {}dB | 12kHz {}dB",
                    format_signed_centi(s.bands.sub_60hz),
                    format_signed_centi(s.bands.low_250hz),
                    format_signed_centi(s.bands.mid_1khz),
                    format_signed_centi(s.bands.high_mid_4khz),
                    format_signed_centi(s.bands.air_12khz),
                );
                println!(
                    "split  L:Jack {}/1000 (pan {}/1000) | R:AirPods {}/1000 (trim {}dB)",
                    s.split_ear.left_jack_vol_permille,
                    s.split_ear.left_jack_pan_permille,
                    s.split_ear.right_airpods_right_permille,
                    format_signed_centi(s.split_ear.transducer_trim_centi_db),
                );
                println!(
                    "wupz   fold {}  diff {}B  popcount {}",
                    fold_hex, s.wupz_byte_diff, s.wupz_popcount
                );
            }
            ExitCode::SUCCESS
        }
        "transcribe" => {
            let pos = positional(rest);
            let Some(path) = pos.first() else {
                eprintln!("error: transcribe: need an audio file");
                return ExitCode::from(1);
            };
            if !Path::new(path).exists() {
                eprintln!("error: transcribe: no such file: {path}");
                return ExitCode::from(1);
            }
            match transcribe_wav_file(path, locale) {
                Ok(res) => {
                    let fold_hex = format!("0x{:016x}", res.eq_snapshot.wupz_fold);
                    if json_out {
                        println!(
                            "{{\"ok\":true,\"text\":\"{}\",\"code\":\"{}\",\"magnitude\":{},\"valence_pq\":\"{}\",\"arousal_pq\":\"{}\",\"dominance_pq\":\"{}\",\"noise_class\":\"{}\",\"level_dbfs_pq\":\"{}\",\"salience_pq\":\"{}\",\"f0_hz_pq\":\"{}\",\"wupz_fold\":\"{}\",\"duration_pq\":\"{}\",\"backend\":\"{}\"}}",
                            json_escape(&res.text),
                            res.emotion.hex,
                            res.emotion.magnitude(),
                            res.vad_pq.valence,
                            res.vad_pq.arousal,
                            res.vad_pq.dominance,
                            res.eq_snapshot.noise.classification.label(),
                            res.eq_snapshot.noise.level_dbfs_pq(),
                            res.eq_snapshot.salience_pq,
                            res.eq_snapshot.estimated_f0_pq,
                            fold_hex,
                            res.duration_pq,
                            json_escape(&res.backend)
                        );
                    } else {
                        println!(
                            "{}",
                            if res.text.is_empty() {
                                "(no speech)"
                            } else {
                                &res.text
                            }
                        );
                        println!(
                            "code  {}   noise {} ({} dBFS)   salience {}   wupz {}",
                            res.emotion.hex,
                            res.eq_snapshot.noise.classification.label(),
                            format_deci_db(res.eq_snapshot.noise.level_deci_dbfs),
                            res.eq_snapshot.salience_pq,
                            fold_hex
                        );
                    }
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    if json_out {
                        println!("{{\"ok\":false,\"error\":\"{}\"}}", json_escape(&e));
                    } else {
                        eprintln!("error: transcribe: {e}");
                    }
                    ExitCode::from(1)
                }
            }
        }
        "live" => {
            let pos = positional(rest);
            let secs: u64 = pos
                .first()
                .and_then(|s| s.parse().ok())
                .unwrap_or(5)
                .clamp(1, 86_400);
            let xdg_runtime =
                env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".to_string());
            let rec_file = format!("/tmp/kotoro_live_{}_{}.wav", std::process::id(), now_secs());
            let _ = Command::new("sh")
                .env("XDG_RUNTIME_DIR", &xdg_runtime)
                .args([
                    "-c",
                    &format!(
                        "MIC_SRC=$(pactl list sources short 2>/dev/null | awk '/alsa_input.*Mic1__source/{{print $2; exit}}'); \
                         if [ -n \"$MIC_SRC\" ]; then pactl set-default-source \"$MIC_SRC\" 2>/dev/null || true; fi; \
                         timeout {secs}s pw-record --rate=16000 --channels=1 --format=s16 '{rec_file}' >/dev/null 2>&1 || arecord -f S16_LE -r 16000 -c 1 -d {secs} '{rec_file}' >/dev/null 2>&1"
                    ),
                ])
                .status();

            if !Path::new(&rec_file).exists() {
                eprintln!("error: live: could not capture microphone audio");
                return ExitCode::from(1);
            }

            let out = transcribe_wav_file(&rec_file, locale);
            let _ = fs::remove_file(&rec_file);
            match out {
                Ok(res) => {
                    let fold_hex = format!("0x{:016x}", res.eq_snapshot.wupz_fold);
                    if json_out {
                        println!(
                            "{{\"ok\":true,\"text\":\"{}\",\"code\":\"{}\",\"magnitude\":{},\"noise_class\":\"{}\",\"level_dbfs_pq\":\"{}\",\"salience_pq\":\"{}\",\"wupz_fold\":\"{}\",\"take_seconds\":{},\"backend\":\"{}\"}}",
                            json_escape(&res.text),
                            res.emotion.hex,
                            res.emotion.magnitude(),
                            res.eq_snapshot.noise.classification.label(),
                            res.eq_snapshot.noise.level_dbfs_pq(),
                            res.eq_snapshot.salience_pq,
                            fold_hex,
                            secs,
                            json_escape(&res.backend)
                        );
                    } else {
                        println!(
                            "[{:<7} {} dBFS | {}] {}",
                            res.eq_snapshot.noise.classification.label(),
                            format_deci_db(res.eq_snapshot.noise.level_deci_dbfs),
                            res.emotion.hex,
                            if res.text.is_empty() {
                                "(no speech)"
                            } else {
                                &res.text
                            }
                        );
                        println!("take  {secs} s");
                    }
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("error: live: {e}");
                    ExitCode::from(1)
                }
            }
        }
        other => {
            eprintln!("error: unknown command '{other}'\n\n{USAGE}");
            ExitCode::from(1)
        }
    }
}
