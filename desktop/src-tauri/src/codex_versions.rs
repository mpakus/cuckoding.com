//! Exact conformance-tested execution cohorts, separate from setup-only clients.
pub const TASK: &[&str] = &["0.162.0-alpha.17.2", "0.163.0-alpha.11.2"];

pub fn from_output(output: &[u8]) -> Option<&'static str> {
    TASK.iter()
        .copied()
        .find(|v| output == format!("codex-cli {v}\n").as_bytes())
}

#[cfg(test)]
mod tests {
    #[test]
    fn only_exact_cohorts_are_admitted() {
        for version in super::TASK {
            assert_eq!(
                super::from_output(format!("codex-cli {version}\n").as_bytes()),
                Some(*version)
            );
        }
        for unknown in [
            b"codex-cli 0.146.0\n".as_slice(),
            b"codex-cli 0.163.0-alpha.11.3\n",
            b"codex-cli 0.163.0-alpha.11.2\nextra",
        ] {
            assert_eq!(super::from_output(unknown), None);
        }
    }
}
