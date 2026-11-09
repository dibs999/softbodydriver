#pragma once
#include <algorithm>
#include <cmath>
#include <complex>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace stability {
constexpr double pi = 3.14159265358979323846;
struct Spectrum {
    double highRms = 0, totalRms = 0, binHz = 0;
    std::vector<double> power; // one-sided mean-square contribution per bin, not PSD
};
inline Spectrum analyze(const std::vector<double>& samples, double sampleHz, double cutoffHz = 10) {
    if (samples.size() < 4 || sampleHz <= 2 * cutoffHz) throw std::invalid_argument("invalid spectrum sampling");
    const std::size_t n = samples.size();
    std::size_t fftSize = 1;
    while (fftSize < n) fftSize *= 2;
    std::vector<std::complex<double>> a(fftSize);
    const double mean = std::accumulate(samples.begin(), samples.end(), 0.0) / static_cast<double>(n);
    double numerator = 0, denominator = 0;
    for (std::size_t i = 0; i < n; ++i) {
        const double t = static_cast<double>(i) - 0.5 * static_cast<double>(n - 1);
        numerator += t * (samples[i] - mean); denominator += t * t;
    }
    const double slope = numerator / denominator;
    double windowEnergy = 0;
    for (std::size_t i = 0; i < n; ++i) {
        const double window = 0.5 - 0.5 * std::cos(2 * pi * static_cast<double>(i) / static_cast<double>(n - 1));
        const double t = static_cast<double>(i) - 0.5 * static_cast<double>(n - 1);
        a[i] = (samples[i] - mean - slope * t) * window;
        windowEnergy += window * window;
    }
    for (std::size_t i = 1, j = 0; i < fftSize; ++i) {
        std::size_t bit = fftSize >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (std::size_t width = 2; width <= fftSize; width *= 2) {
        const auto step = std::polar(1.0, -2 * pi / static_cast<double>(width));
        for (std::size_t offset = 0; offset < fftSize; offset += width) {
            std::complex<double> phase{1, 0};
            for (std::size_t j = 0; j < width / 2; ++j) {
                const auto even = a[offset + j], odd = phase * a[offset + j + width / 2];
                a[offset + j] = even + odd; a[offset + j + width / 2] = even - odd;
                phase *= step;
            }
        }
    }
    Spectrum result;
    result.binHz = sampleHz / static_cast<double>(fftSize);
    result.power.resize(fftSize / 2 + 1);
    double high = 0, total = 0;
    for (std::size_t k = 0; k < result.power.size(); ++k) {
        const double sided = (k == 0 || k == fftSize / 2) ? 1.0 : 2.0;
        const double power = sided * std::norm(a[k]) / (static_cast<double>(fftSize) * windowEnergy);
        result.power[k] = power; total += power;
        if (static_cast<double>(k) * result.binHz > cutoffHz) high += power;
    }
    result.highRms = std::sqrt(high); result.totalRms = std::sqrt(total);
    return result;
}
inline bool selfTest() {
    constexpr double fs = 2000;
    std::vector<double> low(20000), high(low.size()), mix(low.size()), ramp(low.size()), nyquist(low.size());
    for (std::size_t i = 0; i < low.size(); ++i) {
        const double t = static_cast<double>(i) / fs;
        low[i] = 7 * std::sin(2 * pi * 3 * t);
        high[i] = 2 * std::sin(2 * pi * 30 * t);
        ramp[i] = 120 + 3 * t;
        mix[i] = low[i] + high[i] + ramp[i];
        nyquist[i] = i % 2 ? -1.0 : 1.0;
    }
    return analyze(low, fs).highRms < 1e-4 && analyze(ramp, fs).totalRms < 1e-10 &&
        std::abs(analyze(high, fs).highRms - std::sqrt(2.0)) < 1e-5 &&
        std::abs(analyze(mix, fs).highRms - std::sqrt(2.0)) < 1e-5 &&
        std::abs(analyze(high, fs).totalRms - std::sqrt(2.0)) < 1e-4 &&
        std::abs(analyze(nyquist, fs).highRms - 1.0) < 1e-5;
}
} // namespace stability
