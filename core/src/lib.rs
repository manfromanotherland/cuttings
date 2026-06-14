// SPDX-License-Identifier: MIT

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_semver() {
        let v = version();
        assert!(!v.is_empty());
        assert_eq!(v.split('.').count(), 3);
    }
}
