// SPDX-License-Identifier: MIT

use std::sync::{Mutex, OnceLock};

use ulid::{Generator, Ulid};

/// Generate a new ULID string (26-char Crockford Base32).
///
/// IDs are **monotonically increasing**: a process-wide generator increments
/// the random component for IDs created within the same millisecond, so IDs
/// produced in sequence always sort in creation order. (Plain `Ulid::new()`
/// only sorts across milliseconds — within one, its random suffix is
/// unordered, which would let two saves in the same millisecond sort out of
/// insertion order.)
pub fn new_id() -> String {
    static GENERATOR: OnceLock<Mutex<Generator>> = OnceLock::new();
    let generator = GENERATOR.get_or_init(|| Mutex::new(Generator::new()));
    let mut guard = generator.lock().unwrap_or_else(|e| e.into_inner());
    // `generate` only errors on monotonic overflow within a single millisecond
    // (practically impossible) or if the system clock moves backwards; fall
    // back to a fresh random ULID so we always return a valid 26-char id.
    guard.generate().unwrap_or_else(|_| Ulid::new()).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_is_26_chars() {
        let id = new_id();
        assert_eq!(id.len(), 26);
    }

    #[test]
    fn ids_are_sorted_by_creation_order() {
        // The monotonic generator must keep ids strictly increasing even when
        // many are produced within the same millisecond — a tight loop is the
        // worst case for the old random-suffix behaviour.
        let mut prev = new_id();
        for _ in 0..1000 {
            let next = new_id();
            assert!(prev < next, "{prev} should sort before {next}");
            prev = next;
        }
    }

    #[test]
    fn ids_are_unique() {
        let a = new_id();
        let b = new_id();
        assert_ne!(a, b);
    }
}
