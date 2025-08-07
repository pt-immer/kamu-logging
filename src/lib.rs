#[cfg(all(feature = "systemd", feature = "wasm32"))]
compile_error!("Feature \"systemd\" can't be combined with \"wasm32\".");

#[cfg(not(any(feature = "systemd", feature = "wasm32")))]
compile_error!("At least feature \"systemd\" or \"wasm32\" must be enabled.");

#[cfg(debug_assertions)]
#[cfg(feature = "systemd")]
const TRACING_FILTER: &str = "debug";
#[cfg(not(debug_assertions))]
#[cfg(feature = "systemd")]
const TRACING_FILTER: &str = "info";

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("{0}")]
    IO(#[from] std::io::Error),
    #[error("{0}")]
    TracingGlobal(#[from] tracing::subscriber::SetGlobalDefaultError),
    #[error("{0}")]
    TracingLog(#[from] tracing_log::log::SetLoggerError),
}

// Pull in extension traits when building the systemd subscriber. These
// imports are conditionally compiled so that builds which do not enable
// the `systemd` feature don’t pull in unused items. The `SubscriberExt`
// trait provides the `with` method used to layer subscribers, and
// `SubscriberInitExt` exposes the `try_init` method to install the
// configured subscriber as the global default.
#[cfg(feature = "systemd")]
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
pub fn init() -> std::result::Result<(), Error> {
    #[cfg(feature = "systemd")]
    init_systemd()?;
    #[cfg(feature = "wasm32")]
    init_wasm32()?;

    tracing::info!("Logging initialized");

    Ok(())
}

#[cfg(feature = "systemd")]
fn init_systemd() -> std::result::Result<(), Error> {
    // Install a bridge so that messages logged via the `log` crate are
    // forwarded into the `tracing` subscriber. Without this bridge, log
    // calls in dependencies would be lost. If the bridge has already been
    // installed, an error will be returned here and bubbled up.
    tracing_log::LogTracer::init()?;

    // Build an `EnvFilter` from the `RUST_LOG` environment variable. If
    // parsing fails or the variable is absent, fall back to the
    // compile‑time default filter defined above (`debug` in debug
    // builds and `info` otherwise).
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(TRACING_FILTER));

    // Start with a registry and attach the filter. Subsequent layers will
    // be added to this base subscriber.
    let base = tracing_subscriber::registry().with(filter);

    if console::Term::stdout().is_term() {
        // When running in an interactive terminal, use a formatted
        // subscriber that emits human‑readable logs. Include span
        // close events, ANSI colours, line numbers and thread IDs.
        let fmt_layer = tracing_subscriber::fmt::layer()
            .with_span_events(tracing_subscriber::fmt::format::FmtSpan::CLOSE)
            .with_ansi(true)
            .with_line_number(true)
            .with_thread_ids(true);

        let subscriber = base.with(fmt_layer);
        // `try_init` sets this subscriber as the global default. It will
        // return an error if a global subscriber has already been set.
        subscriber.try_init()?;
    } else {
        // Otherwise, assume journald is available and use a journald
        // subscriber. This will forward structured logs to the system
        // journal. If journald cannot be initialised it will return an
        // error which propagates up to the caller.
        let journald_layer = tracing_journald::layer()?;
        let subscriber = base.with(journald_layer);
        subscriber.try_init()?;
    }

    Ok(())
}

#[cfg(feature = "wasm32")]
fn init_wasm32() -> std::result::Result<(), Error> {
    console_error_panic_hook::set_once();
    wasm_tracing::set_as_global_default();

    Ok(())
}

#[cfg(feature = "logging-actix-web")]
pub fn get_actix_web_logger()
-> tracing_actix_web::TracingLogger<tracing_actix_web::DefaultRootSpanBuilder> {
    tracing_actix_web::TracingLogger::default()
}
