//! Correlation-id helpers for distributed tracing.
//!
//! Provides a header-chain extractor and span constructors so consumers
//! (HTTP middlewares, queue workers) can attach a consistent
//! `correlation_id` field to every span without re-implementing the
//! convention per service.

/// Default headers checked, in priority order, by [`extract_from_headers`].
pub const DEFAULT_HEADER_CHAIN: &[&str] = &["x-request-id", "x-correlation-id", "traceparent"];

/// Extract a correlation id from a header bag using a configurable getter.
///
/// `headers` is opaque; the caller supplies `get` which performs the
/// case-insensitive lookup natural to its header type. `chain` is the
/// ordered list of header names to try. The first header that yields a
/// non-empty value wins.
///
/// `traceparent` values are reduced to their trace-id segment per W3C
/// Trace Context (`<version>-<trace-id>-<span-id>-<flags>`).
pub fn extract_from_headers<H, F>(headers: &H, chain: &[&str], get: F) -> Option<String>
where
    F: Fn(&H, &str) -> Option<String>,
{
    for &name in chain {
        if let Some(value) = get(headers, name) {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                continue;
            }
            if name.eq_ignore_ascii_case("traceparent") {
                if let Some(trace_id) = parse_traceparent_trace_id(trimmed) {
                    return Some(trace_id.to_owned());
                }
                continue;
            }
            return Some(trimmed.to_owned());
        }
    }
    None
}

/// Parse the trace-id segment from a W3C `traceparent` header.
///
/// Format: `<version>-<trace-id>-<parent-id>-<trace-flags>`. Returns the
/// trace-id segment if present and well-formed-enough to use as an id.
#[must_use]
pub fn parse_traceparent_trace_id(traceparent: &str) -> Option<&str> {
    let mut parts = traceparent.split('-');
    let _version = parts.next()?;
    let trace_id = parts.next()?;
    if trace_id.len() != 32 || !trace_id.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(trace_id)
}

/// Run a synchronous closure inside a span carrying `correlation_id`.
///
/// ```
/// # use kamu_logging::correlation::with_id;
/// with_id("req-abc123", || {
///     tracing::info!("inside correlation span");
/// });
/// ```
pub fn with_id<F, R>(id: impl Into<String>, f: F) -> R
where
    F: FnOnce() -> R,
{
    let id = id.into();
    let span = tracing::info_span!("correlation", correlation_id = %id);
    let _enter = span.enter();
    f()
}

/// Build a span carrying `correlation_id`. Useful when the caller wants to
/// control entry/exit explicitly or attach to a future via
/// [`tracing::Instrument`].
#[must_use]
pub fn span(id: impl AsRef<str>) -> tracing::Span {
    tracing::info_span!("correlation", correlation_id = %id.as_ref())
}
