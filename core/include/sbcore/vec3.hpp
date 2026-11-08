// Minimal 3D math for the soft-body core. Double precision on purpose:
// large maps + very stiff springs at 2000 Hz benefit from the extra precision.
#pragma once

#include <cmath>
#include <limits>

namespace sb {

using real = double;
constexpr real kInf = std::numeric_limits<real>::infinity();

struct Vec3 {
    real x = 0, y = 0, z = 0;

    constexpr Vec3() = default;
    constexpr Vec3(real x_, real y_, real z_) : x(x_), y(y_), z(z_) {}

    constexpr Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
    constexpr Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
    constexpr Vec3 operator-() const { return {-x, -y, -z}; }
    constexpr Vec3 operator*(real s) const { return {x * s, y * s, z * s}; }
    constexpr Vec3 operator/(real s) const { return {x / s, y / s, z / s}; }
    Vec3& operator+=(const Vec3& o) { x += o.x; y += o.y; z += o.z; return *this; }
    Vec3& operator-=(const Vec3& o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
    Vec3& operator*=(real s) { x *= s; y *= s; z *= s; return *this; }

    constexpr real& operator[](int i) { return i == 0 ? x : (i == 1 ? y : z); }
    constexpr real operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }
};

constexpr Vec3 operator*(real s, const Vec3& v) { return v * s; }
constexpr real dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
constexpr Vec3 cross(const Vec3& a, const Vec3& b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline real length(const Vec3& v) { return std::sqrt(dot(v, v)); }
constexpr real lengthSq(const Vec3& v) { return dot(v, v); }
inline Vec3 normalize(const Vec3& v) {
    const real l = length(v);
    return l > real(1e-12) ? v / l : Vec3{0, 0, 0};
}
inline bool isFinite(const Vec3& v) { return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z); }

/// Row-major 3x3 matrix (used for oriented colliders).
struct Mat3 {
    real m[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};

    static Mat3 identity() { return {}; }

    Vec3 operator*(const Vec3& v) const {
        return {m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
                m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
                m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z};
    }
    Mat3 operator*(const Mat3& o) const {
        Mat3 r;
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                r.m[i][j] = m[i][0] * o.m[0][j] + m[i][1] * o.m[1][j] + m[i][2] * o.m[2][j];
        return r;
    }
    Mat3 transposed() const {
        Mat3 r;
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j) r.m[i][j] = m[j][i];
        return r;
    }

    /// Rotation from Euler angles in radians, applied in order: X (pitch), Y (yaw), Z (roll).
    /// Resulting matrix = Rz * Ry * Rx.
    static Mat3 fromEuler(real rx, real ry, real rz) {
        const real cx = std::cos(rx), sx = std::sin(rx);
        const real cy = std::cos(ry), sy = std::sin(ry);
        const real cz = std::cos(rz), sz = std::sin(rz);
        Mat3 X, Y, Z;
        X.m[1][1] = cx; X.m[1][2] = -sx; X.m[2][1] = sx; X.m[2][2] = cx;
        Y.m[0][0] = cy; Y.m[0][2] = sy; Y.m[2][0] = -sy; Y.m[2][2] = cy;
        Z.m[0][0] = cz; Z.m[0][1] = -sz; Z.m[1][0] = sz; Z.m[1][1] = cz;
        return Z * Y * X;
    }
};

}  // namespace sb
