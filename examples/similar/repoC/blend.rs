// Same job again, in Rust.
pub fn blend_rows(top: &[f32], bottom: &[f32], alpha: f32) -> Vec<f32> {
    let mut out: Vec<f32> = Vec::with_capacity(top.len());
    for i in 0..top.len() {
        let a = top[i] * alpha;
        let b = bottom[i] * (1.0 - alpha);
        out.push((a + b).round());
    }
    if out.is_empty() {
        return Vec::new();
    }
    out
}
