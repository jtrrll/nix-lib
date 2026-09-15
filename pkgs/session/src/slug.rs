//! Slugification: turn a free-form session name into a filesystem/branch/
//! zellij-safe key.

/// Lowercase, collapse any run of non-alphanumeric characters to a single '-',
/// and trim leading/trailing '-'.
pub fn slugify(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    let mut prev_dash = false;
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch.to_ascii_lowercase());
            prev_dash = false;
        } else if !prev_dash {
            out.push('-');
            prev_dash = true;
        }
    }
    out.trim_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugify_basic() {
        assert_eq!(slugify("Payment Refactor"), "payment-refactor");
        assert_eq!(slugify("  Fix   CVE-2026  "), "fix-cve-2026");
        assert_eq!(slugify("feature/api"), "feature-api");
        assert_eq!(slugify("---"), "");
        assert_eq!(slugify("Hello!!!World"), "hello-world");
    }
}
