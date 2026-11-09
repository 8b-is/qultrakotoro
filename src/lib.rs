//! qUltraKotoro — superwhisper on steroids — on-device STT + an emotional QuantTern code.
//!
//! 100% Pure-Rust, Zero-Dependency, Zero-Float (`p/q` Rational & Integer DSP) implementation
//! for Sovereign Linux (`CachyOS` / `Hyprland` / `Qwave` / `PipeWire` / `ggml-large-v3-turbo`)
//! and cross-platform CLI (`kotorocli` / `qultrakotoro`).
//!
//! Unites four sovereign primitives in one deterministic, offline-first loop:
//! 1. **QuantTern** (`Trit`, `VadPq`, `EmotionCode`, `EmotionTagger`): Quantizes Valence · Arousal ·
//!    Dominance (`-1/1 .. +1/1`) in exact `p/q` rationals into `{−1, 0, +1}` trits and packs
//!    4 trits per byte (`−1→0b00 · 0→0b01 · +1→0b10`) with a printable `qt:xx` hex tag.
//! 2. **NoiseDetector** (`NoiseClass::{Silence, Quiet, Ambient, Noisy}`, `NoiseProfilePq`):
//!    Integer RMS power & peak dBFS (`deci-dBFS` / `p/q`) and exact Zero-Crossing Rate (`crossings / (N-1)`).
//! 3. **MarineSalience & DynamicEqualizer**: O(1) time-domain peak-to-peak vocal salience (`50..640 Hz`)
//!    driving a 5-band Liquid Time-Constant (LTC) equalizer (`60Hz, 250Hz, 1kHz, 4kHz, 12kHz`),
//!    Split-Ear routing, and 32-byte `WupzFrame` (`xor_fold`, `byte_diff`, `popcount`).
//! 4. **On-Device STT Engine**: Marine Salience boundary trimmer + hot loopback `:8785`
//!    (`ggml-large-v3-turbo-q5_0.bin`), `liquid-rust :8786`, or local `whisper-cli` / `kokoro-speak`,
//!    fusing acoustic VAD + lexical `EmotionTagger` VAD into the `qt:` emotional code.

use std::fmt;
use std::fs;
use std::io::{Read, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

// ============================================================================
// 1. Exact Reduced Rational p/q Arithmetic (Zero Authored Floats)
// ============================================================================

/// Greatest common divisor using division-free binary Stein's algorithm.
pub const fn gcd_u64(mut a: u64, mut b: u64) -> u64 {
    if a == 0 {
        return b;
    }
    if b == 0 {
        return a;
    }
    let shift = (a | b).trailing_zeros();
    a >>= a.trailing_zeros();
    loop {
        b >>= b.trailing_zeros();
        if a > b {
            let t = a;
            a = b;
            b = t;
        }
        b -= a;
        if b == 0 {
            break;
        }
    }
    a << shift
}

/// Exact reduced rational `num / den` (`den > 0`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct RationalPq {
    pub num: i64,
    pub den: u64,
}

impl RationalPq {
    pub const ZERO: Self = Self { num: 0, den: 1 };
    pub const ONE: Self = Self { num: 1, den: 1 };
    pub const NEG_ONE: Self = Self { num: -1, den: 1 };

    pub const fn new(num: i64, den: u64) -> Option<Self> {
        if den == 0 {
            return None;
        }
        if num == 0 {
            return Some(Self::ZERO);
        }
        let abs_n = num.unsigned_abs();
        let g = gcd_u64(abs_n, den);
        let r_den = den / g;
        let r_abs = (abs_n / g) as i64;
        let r_num = if num < 0 { -r_abs } else { r_abs };
        Some(Self {
            num: r_num,
            den: r_den,
        })
    }

    pub const fn new_unchecked(num: i64, den: u64) -> Self {
        match Self::new(num, den) {
            Some(r) => r,
            None => Self::ZERO,
        }
    }

    pub const fn integer(n: i64) -> Self {
        Self { num: n, den: 1 }
    }

    /// Clamp a rational into `[-1/1, +1/1]`.
    pub const fn clamp_unit(self) -> Self {
        let d = self.den as i64;
        if self.num > d {
            Self::ONE
        } else if self.num < -d {
            Self::NEG_ONE
        } else {
            self
        }
    }

    /// Compare `self` vs `other` using 128-bit cross-multiplication.
    pub const fn cmp_pq(self, other: Self) -> i8 {
        let lhs = (self.num as i128) * (other.den as i128);
        let rhs = (other.num as i128) * (self.den as i128);
        if lhs < rhs {
            -1
        } else if lhs > rhs {
            1
        } else {
            0
        }
    }

    pub const fn add_pq(self, other: Self) -> Self {
        let num = (self.num as i128) * (other.den as i128)
            + (other.num as i128) * (self.den as i128);
        let den = (self.den as u128) * (other.den as u128);
        // Scale down if intermediate exceeds i64/u64
        if den <= u64::MAX as u128 && num >= i64::MIN as i128 && num <= i64::MAX as i128 {
            Self::new_unchecked(num as i64, den as u64)
        } else {
            let scaled_num = (num / 1024) as i64;
            let d = (den / 1024) as u64;
            let scaled_den = if d == 0 { 1 } else { d };
            Self::new_unchecked(scaled_num, scaled_den)
        }
    }

    /// Format as `"num/den"`.
    pub fn to_pq_string(self) -> String {
        format!("{}/{}", self.num, self.den)
    }
}

impl fmt::Display for RationalPq {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.num, self.den)
    }
}

// ============================================================================
// 2. QuantTern — Emotional Ternary Encoding (VAD -> {-1, 0, +1} -> qt:xx)
// ============================================================================

/// Default ternary threshold in exact `p/q` integer math (`33 / 100`).
pub const DEFAULT_THRESHOLD_PQ: RationalPq = RationalPq { num: 33, den: 100 };

/// One balanced ternary trit of the emotional code (`{-1, 0, +1}`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i8)]
pub enum Trit {
    Minus = -1,
    Zero = 0,
    Plus = 1,
}

impl Trit {
    /// Zero-float quantization of an exact `RationalPq` axis to a trit.
    pub const fn from_rational(x: RationalPq, threshold: RationalPq) -> Self {
        let t_num = (threshold.num.unsigned_abs() as i128) * (x.den as i128);
        let x_scaled = (x.num as i128) * (threshold.den as i128);
        if x_scaled >= t_num {
            Trit::Plus
        } else if x_scaled <= -t_num {
            Trit::Minus
        } else {
            Trit::Zero
        }
    }

    pub const fn raw(self) -> i8 {
        self as i8
    }

    pub const fn from_raw(raw: i8) -> Option<Self> {
        match raw {
            -1 => Some(Trit::Minus),
            0 => Some(Trit::Zero),
            1 => Some(Trit::Plus),
            _ => None,
        }
    }

    /// Two-bit gate code: `-1 -> 0b00`, `0 -> 0b01`, `+1 -> 0b10`.
    pub const fn code(self) -> u8 {
        ((self as i8 + 1) as u8) & 0b11
    }

    pub const fn from_code(code: u8) -> Self {
        match code & 0b11 {
            0b00 => Trit::Minus,
            0b01 => Trit::Zero,
            0b10 => Trit::Plus,
            _ => Trit::Zero,
        }
    }
}

/// Zero-Float Valence · Arousal · Dominance, each clamped to `[-1/1, +1/1]`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct VadPq {
    pub valence: RationalPq,
    pub arousal: RationalPq,
    pub dominance: RationalPq,
}

impl VadPq {
    pub const NEUTRAL: Self = Self {
        valence: RationalPq::ZERO,
        arousal: RationalPq::ZERO,
        dominance: RationalPq::ZERO,
    };

    pub const fn new(valence: RationalPq, arousal: RationalPq, dominance: RationalPq) -> Self {
        Self {
            valence: valence.clamp_unit(),
            arousal: arousal.clamp_unit(),
            dominance: dominance.clamp_unit(),
        }
    }

    pub const fn trits(&self, threshold: RationalPq) -> [Trit; 3] {
        [
            Trit::from_rational(self.valence, threshold),
            Trit::from_rational(self.arousal, threshold),
            Trit::from_rational(self.dominance, threshold),
        ]
    }
}

/// A packed emotional code: the trits, the bytes, and a printable `qt:` hex tag.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EmotionCode {
    pub trits: Vec<Trit>,
    pub bytes: Vec<u8>,
    pub hex: String,
}

impl EmotionCode {
    /// How many trits are non-neutral (`!= Trit::Zero`).
    pub fn magnitude(&self) -> usize {
        self.trits.iter().filter(|&&t| t != Trit::Zero).count()
    }

    pub fn is_neutral(&self) -> bool {
        self.magnitude() == 0
    }

    pub fn first_byte(&self) -> u8 {
        self.bytes.first().copied().unwrap_or(0x55)
    }
}

/// Pack trits four-per-byte, LSB first, and compute the `qt:` tag.
pub fn pack_trits(trits: &[Trit]) -> EmotionCode {
    let mut bytes: Vec<u8> = Vec::with_capacity(trits.len().div_ceil(4).max(1));
    if trits.is_empty() {
        bytes.push(0x55);
    } else {
        let mut i = 0;
        while i < trits.len() {
            let mut b: u8 = 0;
            for j in 0..4 {
                let t = trits.get(i + j).copied().unwrap_or(Trit::Zero);
                b |= t.code() << (2 * j as u8);
            }
            bytes.push(b);
            i += 4;
        }
    }
    let mut hex = String::from("qt:");
    for b in &bytes {
        hex.push_str(&format!("{b:02x}"));
    }
    EmotionCode {
        trits: trits.to_vec(),
        bytes,
        hex,
    }
}

/// Unpack gate-coded bytes back into `count` trits.
pub fn unpack_trits(bytes: &[u8], count: usize) -> Vec<Trit> {
    let mut trits = Vec::with_capacity(bytes.len() * 4);
    for &b in bytes {
        for j in 0..4 {
            let code = (b >> (2 * j as u8)) & 0b11;
            trits.push(Trit::from_code(code));
        }
    }
    trits.truncate(count);
    trits
}

/// Encode a `VadPq` reading into an `EmotionCode`.
pub fn encode_vad_pq(vad: VadPq, threshold: RationalPq) -> EmotionCode {
    pack_trits(&vad.trits(threshold))
}

/// Exact `p/q` rational agreement (`0/1 .. 1/1`) between two trit slices.
pub fn agreement_pq(a: &[Trit], b: &[Trit]) -> RationalPq {
    let n = a.len().min(b.len());
    if n == 0 {
        return RationalPq::ONE;
    }
    let hit = (0..n).filter(|&i| a[i] == b[i]).count();
    RationalPq::new_unchecked(hit as i64, n as u64)
}

/// Zero-float `EmotionTagger` matching `KotoroCore.EmotionTagger` in exact `p/q` rationals.
pub struct EmotionTagger;

impl EmotionTagger {
    const POSITIVE: &'static [&'static str] = &[
        "love", "warm", "hope", "light", "soft", "yes", "thanks", "thank", "good",
        "beautiful", "home", "kind", "gentle", "great", "awesome", "sovereign", "peace",
    ];
    const NEGATIVE: &'static [&'static str] = &[
        "hate", "cold", "fear", "no", "lost", "broken", "alone", "dark", "sorry",
        "pain", "never", "tired", "error", "fail", "crash",
    ];
    const HIGH_AROUSAL: &'static [&'static str] = &[
        "wow", "amazing", "hurry", "run", "fire", "now", "go", "yes", "incredible",
        "fast", "ultra", "hey", "aye",
    ];

    /// Compute exact `p/q` `VadPq` from transcript text.
    /// Each positive/negative word contributes `±1` (`* 3 / word_count`),
    /// each high-arousal word contributes `+2/2` (`+1`), and each `'!'` suffix contributes `+1/2`.
    pub fn vad_pq(text: &str) -> VadPq {
        let mut word_count: u64 = 0;
        let mut v_half_units: i64 = 0; // in units of 1/2
        let mut a_half_units: i64 = 0; // in units of 1/2
        let mut d_half_units: i64 = 0;

        for token in text.split_whitespace() {
            let has_bang = token.ends_with('!');
            let clean: String = token
                .chars()
                .filter(|c| c.is_alphabetic())
                .flat_map(|c| c.to_lowercase())
                .collect();
            if clean.is_empty() {
                continue;
            }
            word_count += 1;
            if Self::POSITIVE.contains(&clean.as_str()) {
                v_half_units += 2;
                d_half_units += 1;
            }
            if Self::NEGATIVE.contains(&clean.as_str()) {
                v_half_units -= 2;
                d_half_units -= 1;
            }
            if Self::HIGH_AROUSAL.contains(&clean.as_str()) {
                a_half_units += 2;
                d_half_units += 1;
            }
            if has_bang {
                a_half_units += 1;
            }
        }

        if word_count == 0 {
            return VadPq::NEUTRAL;
        }

        // Scale by 3 / word_count; since units are 1/2, denominator is 2 * word_count.
        let den = 2 * word_count;
        let valence = RationalPq::new_unchecked(v_half_units * 3, den).clamp_unit();
        let arousal = RationalPq::new_unchecked(a_half_units * 3, den).clamp_unit();
        let dominance = RationalPq::new_unchecked(d_half_units * 3, den).clamp_unit();
        VadPq::new(valence, arousal, dominance)
    }

    pub fn code(text: &str) -> EmotionCode {
        encode_vad_pq(Self::vad_pq(text), DEFAULT_THRESHOLD_PQ)
    }
}

// ============================================================================
// 3. NoiseDetector — Integer Soundscape Profiler (Silence / Quiet / Ambient / Noisy)
// ============================================================================

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum NoiseClass {
    Silence = 0, // < -55 dBFS
    Quiet = 1,   // -55 .. -35 dBFS
    Ambient = 2, // -35 .. -18 dBFS
    Noisy = 3,   // >= -18 dBFS
}

impl NoiseClass {
    pub const fn label(self) -> &'static str {
        match self {
            NoiseClass::Silence => "silence",
            NoiseClass::Quiet => "quiet",
            NoiseClass::Ambient => "ambient",
            NoiseClass::Noisy => "noisy",
        }
    }

    /// Classify from integer deci-dBFS (`10 * dBFS`, e.g. `-550` = `-55.0 dBFS`).
    pub const fn classify_deci_dbfs(level_deci_dbfs: i32) -> Self {
        if level_deci_dbfs < -550 {
            NoiseClass::Silence
        } else if level_deci_dbfs < -350 {
            NoiseClass::Quiet
        } else if level_deci_dbfs < -180 {
            NoiseClass::Ambient
        } else {
            NoiseClass::Noisy
        }
    }
}

/// Zero-Float Noise Profile in integer deci-dBFS (`1/10 dB`) and exact `p/q` rationals.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NoiseProfilePq {
    /// Running RMS in tenths of a dBFS (`-800 .. 0`, i.e., `-80.0 .. 0.0 dBFS`).
    pub level_deci_dbfs: i32,
    /// Peak sample power in tenths of a dBFS (`-800 .. 0`).
    pub peak_deci_dbfs: i32,
    /// Exact Zero-Crossing Rate `crossings / (N - 1)` in `[0/1, 1/1]`.
    pub zcr_pq: RationalPq,
    /// Zero-Crossing Rate scaled to permille (`0 .. 1000`).
    pub zcr_permille: u16,
    /// Room noise classification (`Silence | Quiet | Ambient | Noisy`).
    pub classification: NoiseClass,
}

impl NoiseProfilePq {
    pub const SILENCE: Self = Self {
        level_deci_dbfs: -800,
        peak_deci_dbfs: -800,
        zcr_pq: RationalPq::ZERO,
        zcr_permille: 0,
        classification: NoiseClass::Silence,
    };

    pub const fn level_dbfs_pq(&self) -> RationalPq {
        RationalPq::new_unchecked(self.level_deci_dbfs as i64, 10)
    }

    pub const fn peak_dbfs_pq(&self) -> RationalPq {
        RationalPq::new_unchecked(self.peak_deci_dbfs as i64, 10)
    }
}

/// Integer `10 * log10(power_q30 / 2^30)` in tenths of a dB (`deci-dBFS`, `-800 .. 0`).
/// Uses exact integer bit-length (`ilog2`) + 8-entry linear mantissa LUT (`100 * log10(2) = 30.103`).
pub const fn power_q30_to_deci_dbfs(power_q30: u64) -> i32 {
    if power_q30 == 0 {
        return -800;
    }
    const FULL_SCALE_Q30: u64 = 1u64 << 30;
    if power_q30 >= FULL_SCALE_Q30 {
        return 0;
    }
    let lz = power_q30.leading_zeros(); // full_scale has lz = 33
    let bit_pos = 63u32.saturating_sub(lz); // 0..29
    // Fractional top 3 bits below the leading 1
    let shift = if bit_pos >= 3 { bit_pos - 3 } else { 0 };
    let mant_idx = ((power_q30 >> shift) & 0x7) as usize;
    // 100 * log10(1 + k/8) rounded to nearest integer (in hundredths of a dB)
    const MANT_CENTI_DB: [i32; 8] = [0, 51, 97, 138, 176, 211, 243, 273];
    // Each power-of-2 below 2^30 is -3.0103 dB = -30.103 deci-dB = -301.03 centi-dB
    let steps_below_30 = (30i32 - bit_pos as i32) * 1000;
    let centi_db = -((steps_below_30 * 301) / 1000) + MANT_CENTI_DB[mant_idx];
    let deci_db = centi_db / 10;
    if deci_db < -800 {
        -800
    } else if deci_db > 0 {
        0
    } else {
        deci_db
    }
}

/// Deterministic, Zero-Float Integer `NoiseDetector` over 16-bit signed PCM samples (`i16`).
pub struct NoiseDetector {
    /// Smoothing numerator out of 100 (default `20` = `20/100` = `1/5`).
    pub smoothing_pct: u32,
    smoothed_power_q30: u64,
    peak_abs: u32,
    pub profile: NoiseProfilePq,
}

impl Default for NoiseDetector {
    fn default() -> Self {
        Self::new(20)
    }
}

impl NoiseDetector {
    pub const fn new(smoothing_pct: u32) -> Self {
        let s = if smoothing_pct > 100 { 100 } else { smoothing_pct };
        Self {
            smoothing_pct: s,
            smoothed_power_q30: 0,
            peak_abs: 0,
            profile: NoiseProfilePq::SILENCE,
        }
    }

    pub fn reset(&mut self) {
        self.smoothed_power_q30 = 0;
        self.peak_abs = 0;
        self.profile = NoiseProfilePq::SILENCE;
    }

    pub fn ingest_i16(&mut self, samples: &[i16]) -> NoiseProfilePq {
        if samples.is_empty() {
            return self.profile;
        }
        let mut sum_sq: u128 = 0;
        let mut crossings: u64 = 0;
        let mut prev_non_neg = samples[0] >= 0;
        let mut block_peak: u32 = 0;

        for &s in samples {
            let abs_s = (s as i32).unsigned_abs();
            if abs_s > block_peak {
                block_peak = abs_s;
            }
            // s^2 in [0, 32768^2 = 2^30]
            sum_sq += (abs_s as u128) * (abs_s as u128);
            let cur_non_neg = s >= 0;
            if cur_non_neg != prev_non_neg {
                crossings += 1;
            }
            prev_non_neg = cur_non_neg;
        }

        let mean_power_q30 = (sum_sq / (samples.len() as u128)) as u64;
        let a = self.smoothing_pct as u64;
        if self.smoothed_power_q30 == 0 {
            self.smoothed_power_q30 = mean_power_q30;
        } else {
            self.smoothed_power_q30 =
                (a * mean_power_q30 + (100 - a) * self.smoothed_power_q30) / 100;
        }

        if block_peak > self.peak_abs {
            self.peak_abs = block_peak;
        }

        let peak_power_q30 = (self.peak_abs as u64).saturating_mul(self.peak_abs as u64);
        let level_deci = power_q30_to_deci_dbfs(self.smoothed_power_q30);
        let peak_deci = power_q30_to_deci_dbfs(peak_power_q30);

        let (zcr_pq, zcr_permille) = if samples.len() > 1 {
            let denom = (samples.len() - 1) as u64;
            let pq = RationalPq::new_unchecked(crossings as i64, denom);
            let perm = ((crossings * 1000) / denom).min(1000) as u16;
            (pq, perm)
        } else {
            (RationalPq::ZERO, 0)
        };

        self.profile = NoiseProfilePq {
            level_deci_dbfs: level_deci,
            peak_deci_dbfs: peak_deci,
            zcr_pq,
            zcr_permille,
            classification: NoiseClass::classify_deci_dbfs(level_deci),
        };
        self.profile
    }
}

// ============================================================================
// 4. MarineSalience + 5-Band LTC DynamicEqualizer + WupzFrame (ABI v1)
// ============================================================================

/// Zero-Float O(1) Time-Domain Marine Salience Detector (`50..640 Hz` harmonic fundamental).
pub struct MarineSalience {
    /// Clip threshold in `i16` units (`66` ≈ `2 / 1000` of `32768`).
    pub clip_threshold_i16: u32,
    /// EMA alpha in percent (`10` = `1/10`).
    pub alpha_pct: u32,
    prev_sample: i32,
    prev_prev_sample: i32,
    sample_index: u64,
    last_peak_index: Option<u64>,
    pub ema_amp_i16: u32,
    pub ema_period_q8: u32,
}

impl Default for MarineSalience {
    fn default() -> Self {
        Self::new(66, 10)
    }
}

impl MarineSalience {
    pub const fn new(clip_threshold_i16: u32, alpha_pct: u32) -> Self {
        Self {
            clip_threshold_i16,
            alpha_pct,
            prev_sample: 0,
            prev_prev_sample: 0,
            sample_index: 0,
            last_peak_index: None,
            ema_amp_i16: 0,
            ema_period_q8: 0,
        }
    }

    pub fn reset(&mut self) {
        self.prev_sample = 0;
        self.prev_prev_sample = 0;
        self.sample_index = 0;
        self.last_peak_index = None;
        self.ema_amp_i16 = 0;
        self.ema_period_q8 = 0;
    }

    /// Estimated fundamental frequency F0 in Hz as an exact `RationalPq`.
    pub fn estimated_f0_pq(&self, sample_rate: u32) -> RationalPq {
        if self.ema_period_q8 == 0 {
            return RationalPq::ZERO;
        }
        RationalPq::new_unchecked((sample_rate as i64) * 256, self.ema_period_q8 as u64)
    }

    /// Ingest 16-bit PCM samples and return Marine salience in permille (`0 .. 1000`) and `RationalPq`.
    pub fn ingest_i16(&mut self, samples: &[i16], sample_rate: u32) -> (u16, RationalPq) {
        if samples.is_empty() || sample_rate == 0 {
            return (0, RationalPq::ZERO);
        }
        let min_period = (sample_rate / 640).max(1) as u64;
        let max_period = ((sample_rate / 50) as u64).max(min_period + 1);
        let a = self.alpha_pct as u32;

        let mut total_salience_permille: u64 = 0;
        for &s in samples {
            let cur = s as i32;
            let abs_s = cur.unsigned_abs();
            let mut sal_permille: u64 = 0;

            if abs_s >= self.clip_threshold_i16 {
                // Non-peak contribution: 0.1 * (abs_s / 32768) in permille = (abs_s * 100) / 32768
                sal_permille = ((abs_s as u64) * 100) / 32768;
                let is_max = self.prev_prev_sample < self.prev_sample && self.prev_sample > cur;
                if is_max && self.sample_index > 0 {
                    let current_peak = self.sample_index - 1;
                    if let Some(prev_peak) = self.last_peak_index {
                        let period = current_peak.saturating_sub(prev_peak);
                        if period >= min_period && period <= max_period {
                            let amp = self.prev_sample.unsigned_abs();
                            let period_q8 = (period as u32) << 8;
                            if self.ema_period_q8 == 0 {
                                self.ema_amp_i16 = amp;
                                self.ema_period_q8 = period_q8;
                            } else {
                                self.ema_amp_i16 =
                                    (a * amp + (100 - a) * self.ema_amp_i16) / 100;
                                self.ema_period_q8 =
                                    (a * period_q8 + (100 - a) * self.ema_period_q8) / 100;
                            }
                            let j_p_q8 = period_q8.abs_diff(self.ema_period_q8);
                            let j_a_q8 = (amp.abs_diff(self.ema_amp_i16) * 256) / 32768;
                            // jitter_contrib in permille: 1000 * 256 / (256 + j_p_q8 + j_a_q8)
                            let jitter_permille =
                                (256_000u64) / ((256 + j_p_q8 + j_a_q8).max(256) as u64);
                            let amp_permille = ((abs_s as u64) * 400) / 32768;
                            sal_permille = amp_permille + (jitter_permille * 600) / 1000;
                            self.last_peak_index = Some(current_peak);
                        } else if period > max_period {
                            self.last_peak_index = Some(current_peak);
                            self.ema_amp_i16 = 0;
                            self.ema_period_q8 = 0;
                        }
                    } else {
                        self.last_peak_index = Some(current_peak);
                    }
                }
            }

            self.prev_prev_sample = self.prev_sample;
            self.prev_sample = cur;
            self.sample_index += 1;
            total_salience_permille += sal_permille.min(1000);
        }

        let mean_permille = ((total_salience_permille / (samples.len() as u64)).min(1000)) as u16;
        let pq = RationalPq::new_unchecked(mean_permille as i64, 1000);
        (mean_permille, pq)
    }
}

/// 5-Band Liquid Equalizer Curve in integer centi-dB (`1/100 dB`, clamped `-600 .. +600`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EqBandsCentiDb {
    pub sub_60hz: i16,
    pub low_250hz: i16,
    pub mid_1khz: i16,
    pub high_mid_4khz: i16,
    pub air_12khz: i16,
}

impl EqBandsCentiDb {
    pub const FLAT: Self = Self {
        sub_60hz: 0,
        low_250hz: 0,
        mid_1khz: 0,
        high_mid_4khz: 0,
        air_12khz: 0,
    };

    pub const fn clamp_centi(v: i32) -> i16 {
        if v < -600 {
            -600
        } else if v > 600 {
            600
        } else {
            v as i16
        }
    }
}

/// Split-Ear Routing in integer permille (`0..1000`) and centi-dB trim (`-300..+300`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SplitEarRoutingPq {
    pub left_jack_vol_permille: u16,
    pub left_jack_pan_permille: u16,
    pub right_airpods_left_permille: u16,
    pub right_airpods_right_permille: u16,
    pub transducer_trim_centi_db: i16,
}

/// `wupz` ABI v1 32-Byte Frame Fold & Diff (`wupz/wupz-rs/src/fold.rs` compatible).
pub struct WupzFrame;

impl WupzFrame {
    pub const ABI_VERSION: u8 = 1;
    pub const FRAME_BYTES: usize = 32;

    pub fn xor_fold(bytes: &[u8]) -> u64 {
        let full_words_len = bytes.len() & !7;
        let mut acc: u64 = 0;
        let mut i = 0;
        while i < full_words_len {
            acc ^= (bytes[i] as u64) << ((i & 7) * 8);
            i += 1;
        }
        while i < bytes.len() {
            acc ^= bytes[i] as u64;
            i += 1;
        }
        acc
    }

    pub fn byte_diff(a: &[u8], b: &[u8]) -> u64 {
        let n = a.len().min(b.len());
        let mut diff = 0;
        for i in 0..n {
            if a[i] != b[i] {
                diff += 1;
            }
        }
        diff
    }

    pub fn popcount(bytes: &[u8]) -> u64 {
        bytes.iter().map(|b| b.count_ones() as u64).sum()
    }

    pub fn pack_frame(
        noise: &NoiseProfilePq,
        salience_permille: u16,
        bands: &EqBandsCentiDb,
        split_ear: &SplitEarRoutingPq,
        emotion: &EmotionCode,
    ) -> [u8; 32] {
        let mut out = [0u8; 32];
        let mut put_i16 = |offset: usize, val: i16| {
            let le = val.to_le_bytes();
            out[offset] = le[0];
            out[offset + 1] = le[1];
        };
        put_i16(0, noise.level_deci_dbfs.clamp(-32768, 32767) as i16);
        put_i16(2, noise.peak_deci_dbfs.clamp(-32768, 32767) as i16);
        put_i16(4, noise.zcr_permille as i16);
        put_i16(6, salience_permille as i16);
        put_i16(8, bands.sub_60hz);
        put_i16(10, bands.low_250hz);
        put_i16(12, bands.mid_1khz);
        put_i16(14, bands.high_mid_4khz);
        put_i16(16, bands.air_12khz);
        put_i16(18, split_ear.left_jack_vol_permille as i16);
        put_i16(20, split_ear.right_airpods_right_permille as i16);
        put_i16(22, split_ear.transducer_trim_centi_db);
        out[24] = emotion.first_byte();
        out[25] = Self::ABI_VERSION;
        let fold_prefix = Self::xor_fold(&out[0..26]);
        for k in 0..6 {
            out[26 + k] = ((fold_prefix >> (k * 8)) & 0xff) as u8;
        }
        out
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DynamicEqSnapshotPq {
    pub noise: NoiseProfilePq,
    pub salience_permille: u16,
    pub salience_pq: RationalPq,
    pub estimated_f0_pq: RationalPq,
    pub vad_pq: VadPq,
    pub emotion: EmotionCode,
    pub bands: EqBandsCentiDb,
    pub split_ear: SplitEarRoutingPq,
    pub wupz_fold: u64,
    pub wupz_byte_diff: u64,
    pub wupz_popcount: u64,
    pub frame_bytes: [u8; 32],
}

/// Zero-Float Liquid Time-Constant (LTC) Dynamic Environment Equalizer.
pub struct DynamicEqualizer {
    pub noise_detector: NoiseDetector,
    pub marine_detector: MarineSalience,
    pub max_volume: bool,
    state_centi_db: [i32; 5],
    prev_frame: [u8; 32],
}

impl Default for DynamicEqualizer {
    fn default() -> Self {
        Self::new(true)
    }
}

impl DynamicEqualizer {
    pub const fn new(max_volume: bool) -> Self {
        Self {
            noise_detector: NoiseDetector::new(25),
            marine_detector: MarineSalience::new(66, 10),
            max_volume,
            state_centi_db: [0; 5],
            prev_frame: [0u8; 32],
        }
    }

    pub fn ingest_i16(&mut self, samples: &[i16], sample_rate: u32) -> DynamicEqSnapshotPq {
        let noise = self.noise_detector.ingest_i16(samples);
        let (sal_permille, sal_pq) = self.marine_detector.ingest_i16(samples, sample_rate);
        let f0_pq = self.marine_detector.estimated_f0_pq(sample_rate);

        // Loudness normalized into permille [0..1000]: -800 deci-dBFS -> 0, 0 -> 1000
        let loudness_perm = ((noise.level_deci_dbfs + 800).clamp(0, 800) * 1000 / 800) as i64;
        let zcr_perm = noise.zcr_permille as i64;
        let sal_norm_perm = ((sal_permille as i64) * 4).clamp(0, 1000);

        // Acoustic VAD in permille [-1000..+1000] -> RationalPq
        let v_perm = ((sal_norm_perm * 1400 - zcr_perm * 1200 + 200_000) / 1000).clamp(-1000, 1000);
        let a_perm = (loudness_perm * 2 - 1000).clamp(-1000, 1000);
        let peak_norm_perm = ((noise.peak_deci_dbfs + 400).clamp(-400, 400) * 1000 / 400) as i64;
        let d_perm =
            ((sal_norm_perm * 1500 + peak_norm_perm * 500 - 300_000) / 1000).clamp(-1000, 1000);

        let vad_pq = VadPq::new(
            RationalPq::new_unchecked(v_perm, 1000),
            RationalPq::new_unchecked(a_perm, 1000),
            RationalPq::new_unchecked(d_perm, 1000),
        );
        let emotion = encode_vad_pq(vad_pq, DEFAULT_THRESHOLD_PQ);

        // Target EQ gains in centi-dB [-600..+600]
        let s = sal_norm_perm as i32;
        let z = zcr_perm as i32;
        let targets_centi: [i32; 5] = match noise.classification {
            NoiseClass::Silence => [240, 160, 60 + (s * 150) / 1000, 40, 200],
            NoiseClass::Quiet => [
                200,
                120 - (z * 80) / 1000,
                120 + (s * 200) / 1000,
                100 + (s * 120) / 1000,
                220,
            ],
            NoiseClass::Ambient => [
                280,
                -80 + (s * 60) / 1000,
                200 + (s * 220) / 1000,
                240 - (z * 100) / 1000,
                260,
            ],
            NoiseClass::Noisy => [
                360,
                -200,
                280 + (s * 240) / 1000,
                340 - (z * 120) / 1000,
                300,
            ],
        };

        // Integer LTC ODE step: tau_inv_perm = [250, 286, 556, 667, 455]
        const TAU_INV_PERM: [i32; 5] = [250, 286, 556, 667, 455];
        let drive_perm = 350 + (650 * loudness_perm.max(sal_norm_perm) as i32) / 1000;
        for b in 0..5 {
            let rate_perm = TAU_INV_PERM[b] + drive_perm;
            // Rational Padé(1,1) decay approximation for exp(-rate): (2000 - rate) / (2000 + rate)
            let decay_num = (2000 - rate_perm).clamp(100, 1900);
            let decay_den = (2000 + rate_perm).max(1000);
            let asym_centi = (targets_centi[b] * drive_perm) / rate_perm.max(1);
            self.state_centi_db[b] = (self.state_centi_db[b] * decay_num
                + asym_centi * (decay_den - decay_num))
                / decay_den;
        }

        let bands = EqBandsCentiDb {
            sub_60hz: EqBandsCentiDb::clamp_centi(self.state_centi_db[0]),
            low_250hz: EqBandsCentiDb::clamp_centi(self.state_centi_db[1]),
            mid_1khz: EqBandsCentiDb::clamp_centi(self.state_centi_db[2]),
            high_mid_4khz: EqBandsCentiDb::clamp_centi(self.state_centi_db[3]),
            air_12khz: EqBandsCentiDb::clamp_centi(self.state_centi_db[4]),
        };

        let trim_centi = ((bands.air_12khz as i32 - bands.sub_60hz as i32) / 4).clamp(-300, 300) as i16;
        let base_vol_perm = if self.max_volume {
            1000
        } else {
            (700 + (loudness_perm as u16 * 300) / 1000).clamp(650, 1000)
        };
        let split_ear = SplitEarRoutingPq {
            left_jack_vol_permille: base_vol_perm,
            left_jack_pan_permille: 0,
            right_airpods_left_permille: 0,
            right_airpods_right_permille: base_vol_perm,
            transducer_trim_centi_db: trim_centi,
        };

        let frame = WupzFrame::pack_frame(&noise, sal_permille, &bands, &split_ear, &emotion);
        let fold = WupzFrame::xor_fold(&frame);
        let diff = WupzFrame::byte_diff(&frame, &self.prev_frame);
        let pop = WupzFrame::popcount(&frame);
        self.prev_frame = frame;

        DynamicEqSnapshotPq {
            noise,
            salience_permille: sal_permille,
            salience_pq: sal_pq,
            estimated_f0_pq: f0_pq,
            vad_pq,
            emotion,
            bands,
            split_ear,
            wupz_fold: fold,
            wupz_byte_diff: diff,
            wupz_popcount: pop,
            frame_bytes: frame,
        }
    }
}

// ============================================================================
// 5. WAV PCM Decode/Encode + Marine Salience Silence Trimmer + On-Device STT
// ============================================================================

/// Decode 16-bit PCM or 32-bit IEEE float WAV into `(sample_rate, mono_i16_samples)`.
pub fn decode_wav_i16(bytes: &[u8]) -> Option<(u32, Vec<i16>)> {
    if bytes.len() < 44 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return None;
    }
    let mut pos = 12usize;
    let mut audio_format = 1u16;
    let mut channels = 1u16;
    let mut sample_rate = 16_000u32;
    let mut bits_per_sample = 16u16;
    let mut data_slice: Option<&[u8]> = None;

    while pos + 8 <= bytes.len() {
        let id = &bytes[pos..pos + 4];
        let size = u32::from_le_bytes([
            bytes[pos + 4],
            bytes[pos + 5],
            bytes[pos + 6],
            bytes[pos + 7],
        ]) as usize;
        pos += 8;
        let end = (pos + size).min(bytes.len());
        if id == b"fmt " && size >= 16 {
            audio_format = u16::from_le_bytes([bytes[pos], bytes[pos + 1]]);
            channels = u16::from_le_bytes([bytes[pos + 2], bytes[pos + 3]]).max(1);
            sample_rate = u32::from_le_bytes([
                bytes[pos + 4],
                bytes[pos + 5],
                bytes[pos + 6],
                bytes[pos + 7],
            ])
            .max(1);
            bits_per_sample = u16::from_le_bytes([bytes[pos + 14], bytes[pos + 15]]);
        } else if id == b"data" {
            data_slice = Some(&bytes[pos..end]);
            break;
        }
        pos = end + (size & 1);
    }

    let raw = data_slice?;
    let ch = channels as usize;
    if audio_format == 1 && bits_per_sample == 16 {
        let frame_bytes = 2 * ch;
        let frames = raw.len() / frame_bytes;
        let mut out = Vec::with_capacity(frames);
        for f in 0..frames {
            let mut sum: i32 = 0;
            for c in 0..ch {
                let off = f * frame_bytes + c * 2;
                sum += i16::from_le_bytes([raw[off], raw[off + 1]]) as i32;
            }
            out.push((sum / (ch as i32)).clamp(-32768, 32767) as i16);
        }
        Some((sample_rate, out))
    } else {
        None
    }
}

/// Encode mono `i16` PCM into a 44-byte RIFF WAVE container.
pub fn encode_wav_i16(sample_rate: u32, samples: &[i16]) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let riff_len = 36u32.saturating_add(data_len);
    let byte_rate = sample_rate.saturating_mul(2);
    let mut out = Vec::with_capacity(44 + samples.len() * 2);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&riff_len.to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&byte_rate.to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes()); // block align
    out.extend_from_slice(&16u16.to_le_bytes()); // 16-bit
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for &s in samples {
                out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

/// Pure-integer linear resampler from `src_rate` Hz to `dst_rate` Hz (zero floats).
pub fn resample_pcm_i16(pcm: &[i16], src_rate: u32, dst_rate: u32) -> Vec<i16> {
    if pcm.is_empty() || src_rate == 0 || dst_rate == 0 || src_rate == dst_rate {
        return pcm.to_vec();
    }
    let out_len = ((pcm.len() as u64) * (dst_rate as u64) / (src_rate as u64)).max(1) as usize;
    let mut out = Vec::with_capacity(out_len);
    let last_idx = pcm.len() - 1;
    for i in 0..out_len {
        let num = (i as u64) * (src_rate as u64);
        let idx = (num / (dst_rate as u64)) as usize;
        let rem = (num % (dst_rate as u64)) as i64;
        if idx >= last_idx {
            out.push(pcm[last_idx]);
        } else {
            let s0 = pcm[idx] as i64;
            let s1 = pcm[idx + 1] as i64;
            let interp = s0 + ((s1 - s0) * rem) / (dst_rate as i64);
            out.push(interp.clamp(-32768, 32767) as i16);
        }
    }
    out
}

/// Strip leading and trailing silence using integer RMS + Marine Salience gate.
pub fn trim_salient_speech_pcm_i16(pcm: &[i16], sample_rate: u32) -> Vec<i16> {
    if pcm.is_empty() || sample_rate == 0 {
        return Vec::new();
    }
    let win = ((sample_rate as usize) / 50).max(160); // 20ms window
    if pcm.len() <= win * 4 {
        return pcm.to_vec();
    }
    let mut first_active: Option<usize> = None;
    let mut last_active: usize = 0;
    let mut idx = 0;
    while idx < pcm.len() {
        let end = (idx + win).min(pcm.len());
        let slice = &pcm[idx..end];
        let mut peak: u32 = 0;
        let mut sum_abs: u64 = 0;
        for &s in slice {
            let a = (s as i32).unsigned_abs();
            if a > peak {
                peak = a;
            }
            sum_abs += a as u64;
        }
        let mean_abs = sum_abs / (slice.len() as u64);
        if peak >= 380 && mean_abs >= 95 {
            if first_active.is_none() {
                first_active = Some(idx);
            }
            last_active = end;
        }
        idx = end;
    }

    if let Some(start) = first_active {
        let pre_roll = ((sample_rate as usize) * 120) / 1000;
        let post_roll = ((sample_rate as usize) * 160) / 1000;
        let s = start.saturating_sub(pre_roll);
        let e = (last_active + post_roll).min(pcm.len());
        if e > s {
            return pcm[s..e].to_vec();
        }
    }
    pcm.to_vec()
}

/// Result of an on-device `qUltraKotoro` transcription.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KotoroTranscriptResult {
    pub text: String,
    pub backend: String,
    pub duration_pq: RationalPq,
    pub vad_pq: VadPq,
    pub emotion: EmotionCode,
    pub eq_snapshot: DynamicEqSnapshotPq,
}

/// Resolve the best local `ggml-large-v3-turbo` / Whisper model on disk.
pub fn resolve_local_kotoro_model() -> Option<&'static str> {
    const CANDIDATES: &[&str] = &[
        "/home/hue/.local/share/qwave/models/ggml-large-v3-turbo-q5_0.bin",
        "/usr/share/whisper.cpp-model-large-v3-turbo-q5_0/ggml-large-v3-turbo-q5_0.bin",
        "/home/hue/.local/share/qwave/models/ggml-base.en.bin",
        "./models/ggml-large-v3-turbo.bin",
    ];
    for &p in CANDIDATES {
        if Path::new(p).exists() {
            return Some(p);
        }
    }
    None
}

/// Map BCP-47 locale tag (`en-US`, `ja-JP`, `zh-TW`, `nan-TW`, `hu-HU`) to whisper language code.
pub fn locale_to_whisper_lang(locale: &str) -> &'static str {
    let lower = locale.to_ascii_lowercase();
    if lower.starts_with("ja") {
        "ja"
    } else if lower.starts_with("zh") || lower.starts_with("nan") {
        "zh"
    } else if lower.starts_with("hu") {
        "hu"
    } else if lower.starts_with("de") {
        "de"
    } else if lower.starts_with("fr") {
        "fr"
    } else if lower.starts_with("es") {
        "es"
    } else if lower == "auto" {
        "auto"
    } else {
        "en"
    }
}

fn extract_json_str(json: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\"");
    let pos = json.find(&needle)?;
    let after_key = &json[pos + needle.len()..];
    let colon = after_key.find(':')?;
    let rest = after_key[colon + 1..].trim_start();
    if !rest.starts_with('"') {
        return None;
    }
    let mut out = String::new();
    let mut escaped = false;
    for ch in rest[1..].chars() {
        if escaped {
            match ch {
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                other => out.push(other),
            }
            escaped = false;
        } else if ch == '\\' {
            escaped = true;
        } else if ch == '"' {
            return Some(out);
        } else {
            out.push(ch);
        }
    }
    None
}

/// Clean & deduplicate Whisper/LFM transcript hallucinations and repetition loops.
pub fn sanitize_kotoro_transcript(raw: &str) -> String {
    let mut words: Vec<&str> = Vec::new();
    for line in raw.lines() {
        let t = line.trim();
        if t.is_empty()
            || t.starts_with('[')
            || t.starts_with('(')
            || t.contains("BLANK_AUDIO")
            || t.contains("(silence)")
            || t.contains("(music)")
        {
            continue;
        }
        for w in t.split_whitespace() {
            words.push(w);
        }
    }
    // Collapse immediate 1..=8 word stutters
    let mut out: Vec<&str> = Vec::with_capacity(words.len());
    let mut i = 0;
    while i < words.len() {
        let mut skipped = false;
        for span in (1..=8).rev() {
            if out.len() >= span && i + span <= words.len() {
                let prev = &out[out.len() - span..];
                let next = &words[i..i + span];
                if prev
                    .iter()
                    .zip(next.iter())
                    .all(|(a, b)| a.eq_ignore_ascii_case(b))
                {
                    i += span;
                    skipped = true;
                    break;
                }
            }
        }
        if !skipped {
            out.push(words[i]);
            i += 1;
        }
    }
    out.join(" ")
}

/// Transcribe a WAV file completely on-device using `qUltraKotoro` (Marine Salience +
/// NoiseDetector + 5-Band DynamicEqualizer + Hot `:8785` `ggml-large-v3-turbo` / `:8786` `liquid-rust` /
/// `whisper-cli` + fused Acoustic/Lexical `QuantTern` `qt:` code).
pub fn transcribe_wav_file(wav_path: &str, locale: &str) -> Result<KotoroTranscriptResult, String> {
    let raw_bytes = fs::read(wav_path).map_err(|e| format!("cannot read {wav_path}: {e}"))?;
    let (sr, pcm) = decode_wav_i16(&raw_bytes)
        .ok_or_else(|| format!("unsupported or empty 16-bit PCM WAV: {wav_path}"))?;

    let duration_pq = RationalPq::new_unchecked(pcm.len() as i64, sr as u64);

    // 1. Run DynamicEqualizer (NoiseDetector + MarineSalience + WupzFrame) across 4096-sample frames
    let mut eq = DynamicEqualizer::new(true);
    let mut last_snap: Option<DynamicEqSnapshotPq> = None;
    let mut idx = 0;
    while idx < pcm.len() {
        let end = (idx + 4096).min(pcm.len());
        last_snap = Some(eq.ingest_i16(&pcm[idx..end], sr));
        idx = end;
    }
    let eq_snap = last_snap.unwrap_or_else(|| eq.ingest_i16(&[], sr));

    // 2. Trim leading/trailing silence on long recordings (>3s) & resample to 16kHz for hot :8785
    let active_pcm = if pcm.len() > (sr as usize * 3) {
        let trimmed_pcm = trim_salient_speech_pcm_i16(&pcm, sr);
        if trimmed_pcm.len() >= (sr as usize) {
            trimmed_pcm
        } else {
            pcm
        }
    } else {
        pcm
    };
    let pcm_16k = if sr == 16_000 {
        active_pcm
    } else {
        resample_pcm_i16(&active_pcm, sr, 16_000)
    };
    let trimmed_wav = encode_wav_i16(16_000, &pcm_16k);

    let lang = locale_to_whisper_lang(locale);
    let mut transcript_opt: Option<(String, String)> = None;

    // 3a. Tier 1: Hot loopback qUltraKotoro / whisper-server on 127.0.0.1:8785 (0ms model load)
    let addr8785 = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8785);
    if let Ok(mut stream) = TcpStream::connect_timeout(&addr8785, Duration::from_millis(80)) {
        let _ = stream.set_write_timeout(Some(Duration::from_millis(1000)));
        let _ = stream.set_read_timeout(Some(Duration::from_millis(6500)));
        let boundary = "----qUltraKotoroBoundary8bIs";
        let part_fmt = format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n\
             --{boundary}\r\nContent-Disposition: form-data; name=\"temperature\"\r\n\r\n0.0\r\n\
             --{boundary}\r\nContent-Disposition: form-data; name=\"temperature_inc\"\r\n\r\n0.0\r\n\
             --{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
        );
        let part_end = format!("\r\n--{boundary}--\r\n");
        let content_len = part_fmt.len() + trimmed_wav.len() + part_end.len();
        let header = format!(
            "POST /inference HTTP/1.1\r\nHost: 127.0.0.1:8785\r\nContent-Type: multipart/form-data; boundary={boundary}\r\nContent-Length: {content_len}\r\nConnection: close\r\n\r\n"
        );
        if stream.write_all(header.as_bytes()).is_ok()
            && stream.write_all(part_fmt.as_bytes()).is_ok()
            && stream.write_all(&trimmed_wav).is_ok()
            && stream.write_all(part_end.as_bytes()).is_ok()
        {
            let mut resp = String::new();
            if stream.read_to_string(&mut resp).is_ok() {
                if let Some((_, body)) = resp.split_once("\r\n\r\n") {
                    if let Some(tx) = extract_json_str(body, "text") {
                        let clean = sanitize_kotoro_transcript(&tx);
                        if !clean.is_empty() {
                            transcript_opt = Some((
                                clean,
                                "qultrakotoro:8785 (Hot ggml-large-v3-turbo-q5_0 + QuantTern)".to_string(),
                            ));
                        }
                    }
                }
            }
        }
    }

    // 3b. Tier 2: Hot loopback liquid-rust on 127.0.0.1:8786
    if transcript_opt.is_none() {
        let addr8786 = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 8786);
        if let Ok(mut stream) = TcpStream::connect_timeout(&addr8786, Duration::from_millis(65)) {
            let _ = stream.set_write_timeout(Some(Duration::from_millis(800)));
            let _ = stream.set_read_timeout(Some(Duration::from_millis(1600)));
            let header = format!(
                "POST /v1/audio/wav HTTP/1.1\r\nHost: 127.0.0.1:8786\r\nContent-Type: audio/wav\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                trimmed_wav.len()
            );
            if stream.write_all(header.as_bytes()).is_ok() && stream.write_all(&trimmed_wav).is_ok() {
                let mut resp = String::new();
                if stream.read_to_string(&mut resp).is_ok() {
                    if let Some((_, body)) = resp.split_once("\r\n\r\n") {
                        if let Some(tx) = extract_json_str(body, "text") {
                            let clean = sanitize_kotoro_transcript(&tx);
                            if !clean.is_empty() {
                                transcript_opt = Some((
                                    clean,
                                    "qultrakotoro+liquid-rust:8786 (LFM2.5-Audio + QuantTern)".to_string(),
                                ));
                            }
                        }
                    }
                }
            }
        }
    }

    // 3c. Tier 3: Direct local /usr/bin/whisper-cli with ggml-large-v3-turbo-q5_0.bin
    if transcript_opt.is_none() {
        if let Some(model_path) = resolve_local_kotoro_model() {
            if Path::new("/usr/bin/whisper-cli").exists() {
                let tmp_path = format!("/tmp/kotoro_trim_{}.wav", std::process::id());
                let target_wav = if fs::write(&tmp_path, &trimmed_wav).is_ok() {
                    tmp_path.as_str()
                } else {
                    wav_path
                };
                let mel_frames = ((trimmed_wav.len() as u64) / 640).max(1);
                let audio_ctx = ((mel_frames + 64 + 31) & !31).clamp(128, 384).to_string();
                const PROMPT: &str =
                    "Hey Aye, Qwave, qUltraKotoro, Hyprland, Alexiai, Alexandra, Aurora, Sovereign, MEM8, 8b-is, Waybar, WUPZ.";
                if let Ok(out) = Command::new("/usr/bin/whisper-cli")
                    .args([
                        "-m",
                        model_path,
                        "-f",
                        target_wav,
                        "-l",
                        lang,
                        "-nt",
                        "-np",
                        "-sns",
                        "-mc",
                        "0",
                        "-ml",
                        "96",
                        "-ac",
                        &audio_ctx,
                        "-bo",
                        "1",
                        "-bs",
                        "1",
                        "-t",
                        "10",
                        "--prompt",
                        PROMPT,
                    ])
                    .output()
                {
                    let _ = fs::remove_file(&tmp_path);
                    if out.status.success() {
                        let raw = String::from_utf8_lossy(&out.stdout);
                        let clean = sanitize_kotoro_transcript(&raw);
                        if !clean.is_empty() {
                            transcript_opt = Some((
                                clean,
                                "qultrakotoro-cli (ggml-large-v3-turbo-q5_0 + QuantTern)".to_string(),
                            ));
                        }
                    }
                } else {
                    let _ = fs::remove_file(&tmp_path);
                }
            }
        }
    }

    let (text, backend) = transcript_opt.unwrap_or_else(|| {
        (
            String::new(),
            "qultrakotoro (acoustic-only · no speech detected)".to_string(),
        )
    });

    // 4. Fuse lexical EmotionTagger VAD with acoustic DynamicEqualizer VAD when text is present
    let text_vad = EmotionTagger::vad_pq(&text);
    let fused_vad = if text.is_empty() {
        eq_snap.vad_pq
    } else if !encode_vad_pq(text_vad, DEFAULT_THRESHOLD_PQ).is_neutral() {
        // Weight lexical valence + acoustic arousal/dominance in exact p/q rationals
        VadPq::new(
            text_vad.valence,
            if text_vad.arousal != RationalPq::ZERO {
                text_vad.arousal
            } else {
                eq_snap.vad_pq.arousal
            },
            if text_vad.dominance != RationalPq::ZERO {
                text_vad.dominance
            } else {
                eq_snap.vad_pq.dominance
            },
        )
    } else {
        eq_snap.vad_pq
    };
    let emotion = encode_vad_pq(fused_vad, DEFAULT_THRESHOLD_PQ);

    Ok(KotoroTranscriptResult {
        text,
        backend,
        duration_pq,
        vad_pq: fused_vad,
        emotion,
        eq_snapshot: eq_snap,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quanttern_encodes_and_unpacks_exact_pq() {
        let vad = EmotionTagger::vad_pq("i love this warm beautiful hope!");
        let code = encode_vad_pq(vad, DEFAULT_THRESHOLD_PQ);
        assert!(code.hex.starts_with("qt:"));
        assert!(code.magnitude() >= 1);
        let unpacked = unpack_trits(&code.bytes, 3);
        assert_eq!(unpacked.len(), 3);
        assert_eq!(unpacked[0], Trit::Plus);
        assert_eq!(agreement_pq(&code.trits, &unpacked), RationalPq::ONE);
    }

    #[test]
    fn noise_detector_and_dynamic_eq_zero_float() {
        let mut eq = DynamicEqualizer::new(true);
        // Generate 1600 samples of 200 Hz harmonic square-like wave at moderate amplitude
        let mut pcm = Vec::with_capacity(1600);
        for i in 0..1600 {
            let phase = i % 80;
            let sample: i16 = if phase < 40 { 4000 } else { -4000 };
            pcm.push(sample);
        }
        let snap = eq.ingest_i16(&pcm, 16_000);
        assert!(snap.noise.level_deci_dbfs > -550);
        assert_ne!(snap.noise.classification, NoiseClass::Silence);
        assert!(snap.emotion.hex.starts_with("qt:"));
        assert!(snap.wupz_popcount > 0);
    }
}
