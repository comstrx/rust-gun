use criterion::{criterion_group, criterion_main, Criterion};
use demo::Demo;

fn bench_hello(c: &mut Criterion) {
    let mut g = c.benchmark_group("demo::bench");

    g.bench_function("hello_world", |b| {
        b.iter(|| {
            std::hint::black_box(Demo::hello_world());
        });
    });

    g.finish();
}

criterion_group!(benches, bench_hello);
criterion_main!(benches);
