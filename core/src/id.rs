// SPDX-License-Identifier: MIT

use ulid::Ulid;

/// Generate a new ULID string (26-char Crockford Base32, monotonically sortable by time).
pub fn new_id() -> String {
    Ulid::new().to_string()
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
        let a = new_id();
        let b = new_id();
        // ULIDs generated in sequence must sort in that order
        assert!(a <= b);
    }
}
