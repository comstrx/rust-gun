//! Demo crate.

pub struct Demo;

impl Demo {
    #[must_use]
    pub const fn hello_world() -> &'static str {
        "Hello World"
    }
}
