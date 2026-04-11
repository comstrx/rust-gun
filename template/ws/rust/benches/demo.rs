use criterion::{criterion_group, criterion_main, Criterion};
use demo::Demo;

fn bench_demo(c: &mut Criterion) {
    let mut g = c.benchmark_group("demo::bench");

    g.bench_function("Demo::hello_world", |b| {
        b.iter(|| {
            std::hint::black_box(Demo::hello_world());
        });
    });

    g.finish();
}

criterion_group!(benches, bench_demo);
criterion_main!(benches);
