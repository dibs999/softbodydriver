// Visual (render) model of the realistic car generator + flexbody skinning. See car.hpp.
#include <algorithm>
#include <cmath>
#include <functional>
#include <map>
#include <tuple>

#include "car_profile.hpp"
#include "sbcore/car.hpp"

namespace sb {

using namespace detail;

namespace {

class VisBuilder {
public:
    VisBuilder(const SoftBody& body, CarVisual& vis, const std::vector<float>& frames, const CarLayout& layout)
        : body_(body), vis_(vis), frames_(frames), layout_(layout) {}

    std::string partMaterial(const std::string& material, const std::vector<std::uint32_t>& candidates) const {
        if (!layout_.frontBumperNodes.empty() && candidates.data() == layout_.frontBumperNodes.data()) return "bumper_front_" + material;
        if (!layout_.rearBumperNodes.empty() && candidates.data() == layout_.rearBumperNodes.data()) return "bumper_rear_" + material;
        for (std::size_t side = 0; side < layout_.frontDoors.size(); ++side)
            if (!layout_.frontDoors[side].nodes.empty() && candidates.data() == layout_.frontDoors[side].nodes.data())
                return std::string(side == 0 ? "door_left_" : "door_right_") + material;
        for (std::size_t side = 0; side < layout_.rearDoors.size(); ++side)
            if (!layout_.rearDoors[side].nodes.empty() && candidates.data() == layout_.rearDoors[side].nodes.data())
                return std::string(side == 0 ? "rdoor_left_" : "rdoor_right_") + material;
        if (!layout_.tailgateNodes.empty() && candidates.data() == layout_.tailgateNodes.data()) return "tailgate_" + material;
        return material;
    }

    MeshSurface& surf(const std::string& material, bool steeringWheel = false) {
        const auto key = std::make_pair(material, steeringWheel);
        auto it = index_.find(key);
        if (it != index_.end()) return vis_.skinned[it->second];
        vis_.skinned.emplace_back();
        vis_.skinned.back().material = material;
        vis_.skinned.back().steeringWheel = steeringWheel;
        if (material == "glass" || material == "door_left_glass" || material == "door_right_glass" ||
            material == "rdoor_left_glass" || material == "rdoor_right_glass" || material == "tailgate_glass") vis_.skinned.back().doubleSided = true;
        index_[key] = vis_.skinned.size() - 1;
        return vis_.skinned.back();
    }

    VertexSkin skinNearest(const Vec3& p, const std::vector<std::uint32_t>& candidates, std::size_t k = 4) const {
        // Detached fascia meshes use a frame owned entirely by their cage, so
        // translation/rotation never interpolate back toward the passenger cell.
        if (candidates.size() == 8 &&
            (candidates.data() == layout_.frontBumperNodes.data() || candidates.data() == layout_.rearBumperNodes.data())) {
            const Vec3 a = body_.positions()[candidates[0]], d = body_.positions()[candidates[1]] - a;
            return skinLine(p, candidates[0], candidates[1], candidates[2], dot(p - a, d) / lengthSq(d), 0.0);
        }
        for (const DoorLayout* doorPtr : {&layout_.frontDoors[0], &layout_.frontDoors[1], &layout_.rearDoors[0], &layout_.rearDoors[1]}) {
            const DoorLayout& door = *doorPtr;
            if (!door.nodes.empty() && candidates.data() == door.nodes.data()) {
                const auto& nodes = door.nodes;
                const Vec3 a = body_.positions()[nodes[1]], d = body_.positions()[nodes[5]] - a;
                return skinLine(p, nodes[1], nodes[5], nodes[3], dot(p - a, d) / lengthSq(d), 0.0);
            }
        }
        std::array<std::pair<real, std::uint32_t>, 4> best;
        best.fill({1e30, 0});
        for (std::uint32_t c : candidates) {
            const real d = lengthSq(body_.positions()[c] - p);
            if (d < best[3].first) {
                best[3] = {d, c};
                std::sort(best.begin(), best.end());
            }
        }
        VertexSkin s;
        real wsum = 0;
        const std::size_t kk = std::min<std::size_t>(k, candidates.size());
        for (std::size_t i = 0; i < kk; ++i) {
            const real d = std::sqrt(best[i].first);
            const real w = 1.0 / ((d + 0.08) * (d + 0.08));
            s.node[i] = best[i].second;
            s.weight[i] = static_cast<float>(w);
            wsum += w;
        }
        for (std::size_t i = 0; i < kk; ++i) s.weight[i] = static_cast<float>(s.weight[i] / wsum);
        s.local[0][0] = static_cast<float>(p.x);
        s.local[0][1] = static_cast<float>(p.y);
        s.local[0][2] = static_cast<float>(p.z);
        return s;
    }

    /// Line skin: p follows the segment a->b (fraction t + absolute offset s along it), oriented by ref.
    VertexSkin skinLine(const Vec3& p, std::uint32_t a, std::uint32_t b, std::uint32_t ref, real t, real s) const {
        VertexSkin vs;
        vs.node[0] = a;
        vs.node[1] = b;
        vs.node[2] = ref;
        vs.weight[0] = -1.0f;
        vs.weight[1] = static_cast<float>(t);
        vs.weight[2] = static_cast<float>(s);
        const Vec3 pa = body_.positions()[a], pb = body_.positions()[b], pr = body_.positions()[ref];
        const Vec3 e1 = normalize(pb - pa);
        Vec3 e2 = pr - pa;
        e2 = normalize(e2 - e1 * dot(e2, e1));
        const Vec3 e3 = cross(e1, e2);
        const Vec3 base = pa + (pb - pa) * t + e1 * s;
        vs.local[0][0] = static_cast<float>(dot(p - base, e2));
        vs.local[0][1] = static_cast<float>(dot(p - base, e3));
        return vs;
    }

    std::uint32_t vertex(MeshSurface& m, const Vec3& p, const VertexSkin& s) {
        const auto idx = static_cast<std::uint32_t>(m.positions.size() / 3);
        m.positions.push_back(static_cast<float>(p.x));
        m.positions.push_back(static_cast<float>(p.y));
        m.positions.push_back(static_cast<float>(p.z));
        m.normals.insert(m.normals.end(), {0.0f, 1.0f, 0.0f});
        m.skin.push_back(s);
        return idx;
    }

    static void tri(MeshSurface& m, std::uint32_t a, std::uint32_t b, std::uint32_t c) {
        m.indices.push_back(a);
        m.indices.push_back(b);
        m.indices.push_back(c);
    }

    /// Box with given centre, half extents along axes ax, ay, az (unit vectors); skinned to candidates.
    void box(const std::string& mat, const Vec3& c, const Vec3& h, const std::vector<std::uint32_t>& cand,
             const Vec3& ax = {1, 0, 0}, const Vec3& ay = {0, 1, 0}, const Vec3& az = {0, 0, 1}, bool steeringWheel = false) {
        MeshSurface& m = surf(partMaterial(mat, cand), steeringWheel);
        const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
        Vec3 corner[8];
        for (int i = 0; i < 8; ++i)
            corner[i] = c + ax * (h.x * ((i & 4) ? 1 : -1)) + ay * (h.y * ((i & 2) ? 1 : -1)) + az * (h.z * ((i & 1) ? 1 : -1));
        for (const auto& f : faces) {
            std::uint32_t v[4];
            for (int k = 0; k < 4; ++k) v[k] = vertex(m, corner[f[k]], skinNearest(corner[f[k]], cand));
            // Orient outward.
            const Vec3 n = cross(corner[f[1]] - corner[f[0]], corner[f[2]] - corner[f[0]]);
            const Vec3 fc = (corner[f[0]] + corner[f[2]]) * 0.5;
            if (dot(n, fc - c) < 0) {
                tri(m, v[0], v[2], v[1]);
                tri(m, v[0], v[3], v[2]);
            } else {
                tri(m, v[0], v[1], v[2]);
                tri(m, v[0], v[2], v[3]);
            }
        }
    }

    // Welded rounded cuboid for molded cabin parts. The surface is projected
    // onto a box with a spherical bevel; shared edge vertices keep highlights
    // continuous across the radius instead of six primitive-box faces.
    void bevelBox(const std::string& mat, const Vec3& center, const Vec3& half, real radius,
                  const std::vector<std::uint32_t>& candidates,
                  const Vec3& ax = {1, 0, 0}, const Vec3& ay = {0, 1, 0}, const Vec3& az = {0, 0, 1}, bool steering = false) {
        radius = std::min(radius, std::min({half.x, half.y, half.z}) * 0.95);
        MeshSurface& mesh = surf(partMaterial(mat, candidates), steering);
        const Vec3 axes[3] = {ax, ay, az};
        const Vec3 inner = half - Vec3{radius, radius, radius};
        std::map<std::tuple<int, int, int>, std::uint32_t> welded;
        auto coordinate = [&](int axis, int sample) {
            const real h = half[axis];
            const real values[6] = {-h, -h + radius * 0.30, -h + radius, h - radius, h - radius * 0.30, h};
            return values[sample];
        };
        auto add = [&](Vec3 local) {
            Vec3 nearest;
            for (int axis = 0; axis < 3; ++axis) nearest[axis] = std::clamp(local[axis], -inner[axis], inner[axis]);
            local = nearest + normalize(local - nearest) * radius;
            const auto key = std::make_tuple(static_cast<int>(std::round(local.x * 1e6)),
                                            static_cast<int>(std::round(local.y * 1e6)),
                                            static_cast<int>(std::round(local.z * 1e6)));
            auto it = welded.find(key);
            if (it != welded.end()) return it->second;
            const Vec3 p = center + ax * local.x + ay * local.y + az * local.z;
            const auto id = vertex(mesh, p, skinNearest(p, candidates));
            welded[key] = id;
            return id;
        };
        for (int face = 0; face < 3; ++face) {
            const int u = (face + 1) % 3, v = (face + 2) % 3;
            for (real sign : {-1.0, 1.0}) {
                std::uint32_t grid[6][6];
                for (int i = 0; i < 6; ++i) for (int j = 0; j < 6; ++j) {
                    Vec3 p;
                    p[face] = sign * half[face];
                    p[u] = coordinate(u, i);
                    p[v] = coordinate(v, j);
                    grid[i][j] = add(p);
                }
                const bool reverse = dot(cross(axes[u], axes[v]), axes[face] * sign) < 0;
                for (int i = 0; i < 5; ++i) for (int j = 0; j < 5; ++j) {
                    const auto a = grid[i][j], b = grid[i + 1][j], c = grid[i + 1][j + 1], d = grid[i][j + 1];
                    if (reverse) { tri(mesh, a, c, b); tri(mesh, a, d, c); }
                    else { tri(mesh, a, b, c); tri(mesh, a, c, d); }
                }
            }
        }
    }

    // Soft moulded solid (seat cushion, backrest, headrest, console lid): a 2-D section swept from
    // a to b. profile(t) returns the section at t in [0, 1] as (u, v) points around its outline,
    // u along `across`, v along `up`; it may change along the sweep (bolsters, lumbar). Within
    // `round` of either end the section shrinks towards its centre like a stuffed cushion.
    void pillow(const std::string& mat, const Vec3& a, const Vec3& b, const Vec3& across, const Vec3& up,
                const std::function<std::vector<std::pair<real, real>>(real)>& profile, real round,
                const std::vector<std::uint32_t>& cand, int middleStations = 6) {
        MeshSurface& m = surf(partMaterial(mat, cand));
        const real len = length(b - a);
        if (len < 1e-6) return;
        const Vec3 dir = (b - a) / len;
        round = std::min(round, 0.49 * len);
        std::vector<real> ss;
        constexpr int endSteps = 4;
        for (int i = 0; i <= endSteps; ++i) ss.push_back(round * (1.0 - std::cos(0.5 * kPi * i / endSteps)));
        for (int i = 1; i < middleStations; ++i) ss.push_back(round + (len - 2.0 * round) * i / middleStations);
        for (int i = endSteps; i >= 0; --i) ss.push_back(len - round * (1.0 - std::cos(0.5 * kPi * i / endSteps)));
        std::vector<std::vector<std::uint32_t>> rings;
        std::vector<std::uint32_t> centres;
        real area = 0.0;
        for (std::size_t k = 0; k < ss.size(); ++k) {
            const real s = ss[k];
            const auto sec = profile(s / len);
            if (k == 0) {
                for (std::size_t j = 0; j < sec.size(); ++j) {
                    const auto& p = sec[j];
                    const auto& q = sec[(j + 1) % sec.size()];
                    area += p.first * q.second - q.first * p.second;
                }
            }
            real cu = 0.0, cv = 0.0;
            for (const auto& p : sec) { cu += p.first; cv += p.second; }
            cu /= static_cast<real>(sec.size());
            cv /= static_cast<real>(sec.size());
            const real dEnd = std::min(s, len - s);
            const real e = round > 0.0 ? round - std::sqrt(std::max<real>(0.0, round * round - (round - std::min(dEnd, round)) * (round - std::min(dEnd, round)))) : 0.0;
            const Vec3 base = a + dir * s;
            std::vector<std::uint32_t> ring;
            for (const auto& p : sec) {
                const real du = p.first - cu, dv = p.second - cv;
                const real dl = std::sqrt(du * du + dv * dv);
                const real shrink = dl > 1e-9 ? std::min(e, 0.92 * dl) / dl : 0.0;
                const Vec3 q = base + across * (p.first - du * shrink) + up * (p.second - dv * shrink);
                ring.push_back(vertex(m, q, skinNearest(q, cand)));
            }
            rings.push_back(ring);
            if (k == 0 || k + 1 == ss.size()) {
                const Vec3 c = base + across * cu + up * cv;
                centres.push_back(vertex(m, c, skinNearest(c, cand)));
            }
        }
        const bool flip = area * dot(cross(across, up), dir) < 0.0;
        auto emit = [&](std::uint32_t p, std::uint32_t q, std::uint32_t r) { flip ? tri(m, p, r, q) : tri(m, p, q, r); };
        for (std::size_t k = 0; k + 1 < rings.size(); ++k) {
            const auto& r0 = rings[k];
            const auto& r1 = rings[k + 1];
            for (std::size_t j = 0; j < r0.size(); ++j) {
                const std::size_t jn = (j + 1) % r0.size();
                emit(r0[j], r0[jn], r1[jn]);
                emit(r0[j], r1[jn], r1[j]);
            }
        }
        const auto& first = rings.front();
        const auto& last = rings.back();
        for (std::size_t j = 0; j < first.size(); ++j) {
            const std::size_t jn = (j + 1) % first.size();
            emit(centres[0], first[jn], first[j]);
            emit(centres[1], last[j], last[jn]);
        }
    }

    // Open surface through rows of points (all rows the same length): headliner, carpet, wheel
    // arch liners, heat shields. Faces point along `facing` (checked on the first quad); a
    // two-sided sheet gets separate vertices for its back so both sides shade correctly.
    void sheet(const std::string& mat, const std::vector<std::vector<Vec3>>& rows, const Vec3& facing,
               const std::vector<std::uint32_t>& cand, bool twoSided = false) {
        if (rows.size() < 2 || rows[0].size() < 2) return;
        MeshSurface& m = surf(partMaterial(mat, cand));
        const Vec3 n0 = cross(rows[0][1] - rows[0][0], rows[1][1] - rows[0][0]);
        const bool flip = dot(n0, facing) < 0.0;
        for (int side = 0; side < (twoSided ? 2 : 1); ++side) {
            std::vector<std::vector<std::uint32_t>> ids;
            for (const auto& row : rows) {
                std::vector<std::uint32_t> r;
                for (const Vec3& p : row) r.push_back(vertex(m, p, skinNearest(p, cand)));
                ids.push_back(r);
            }
            const bool f = flip != (side == 1);
            for (std::size_t i = 0; i + 1 < ids.size(); ++i)
                for (std::size_t j = 0; j + 1 < ids[i].size(); ++j) {
                    const auto a = ids[i][j], b = ids[i][j + 1], c = ids[i + 1][j + 1], d = ids[i + 1][j];
                    if (f) { tri(m, a, c, b); tri(m, a, d, c); }
                    else { tri(m, a, b, c); tri(m, a, c, d); }
                }
        }
    }

    // Smooth closed housing for mirrors and lamp surrounds, with shared vertices
    // across rings rather than six hard planar box faces.
    void oval(const std::string& mat, const Vec3& center, const Vec3& radii,
              const std::vector<std::uint32_t>& candidates, real rearPlane = -kInf,
              const Vec3& ax = {1, 0, 0}, const Vec3& ay = {0, 1, 0}, const Vec3& az = {0, 0, 1}) {
        MeshSurface& m = surf(partMaterial(mat, candidates));
        constexpr int rings = 10, segments = 20;
        std::vector<std::uint32_t> vertices;
        for (int ring = 0; ring <= rings; ++ring) {
            const real latitude = kPi * ring / rings;
            for (int segment = 0; segment <= segments; ++segment) {
                const real longitude = 2.0 * kPi * segment / segments;
                Vec3 offset{radii.x * std::sin(latitude) * std::cos(longitude),
                            radii.y * std::cos(latitude), radii.z * std::sin(latitude) * std::sin(longitude)};
                offset.x = std::max(offset.x, rearPlane - center.x);
                const Vec3 p = center + ax * offset.x + ay * offset.y + az * offset.z;
                vertices.push_back(vertex(m, p, skinNearest(p, candidates)));
            }
        }
        for (int ring = 0; ring < rings; ++ring) {
            for (int segment = 0; segment < segments; ++segment) {
                const auto a = vertices[static_cast<std::size_t>(ring * (segments + 1) + segment)];
                const auto b = vertices[static_cast<std::size_t>((ring + 1) * (segments + 1) + segment)];
                const auto c = vertices[static_cast<std::size_t>((ring + 1) * (segments + 1) + segment + 1)];
                const auto d = vertices[static_cast<std::size_t>(ring * (segments + 1) + segment + 1)];
                if (ring > 0) tri(m, a, c, b);
                if (ring + 1 < rings) tri(m, a, d, c);
            }
        }
    }

    // Flat elliptical mirror insert: a planar optical surface, not a convex
    // lens or a rectangular plate extending beyond its rounded housing.
    void mirrorInsert(const Vec3& center, real height, real width,
                      const std::vector<std::uint32_t>& candidates, const std::string& fallbackMaterial,
                      const Vec3& up, const Vec3& right) {
        const std::string part = partMaterial("mirror", candidates);
        MeshSurface& mesh = surf(part == "mirror" ? fallbackMaterial : part);
        const auto middle = vertex(mesh, center, skinNearest(center, candidates));
        std::vector<std::uint32_t> rim;
        constexpr int segments = 40;
        for (int i = 0; i < segments; ++i) {
            const real angle = 2.0 * kPi * i / segments;
            const Vec3 p = center + up * (height * std::cos(angle)) + right * (width * std::sin(angle));
            rim.push_back(vertex(mesh, p, skinNearest(p, candidates)));
        }
        for (int i = 0; i < segments; ++i)
            tri(mesh, middle, rim[static_cast<std::size_t>((i + 1) % segments)], rim[static_cast<std::size_t>(i)]);
    }

    // Closed round component between arbitrary points. Skinning to the actual owning
    // assembly keeps accessories with the engine when its mounts break. With innerMat set, the
    // faces whose outward normal points along innerDir (towards the cabin) use that material:
    // pillars are painted outside and trimmed inside.
    void tube(const std::string& mat, const Vec3& a, const Vec3& b, real radius,
              const std::vector<std::uint32_t>& cand, int segments = 12,
              const std::string& innerMat = {}, const Vec3& innerDir = {}) {
        const Vec3 axis = normalize(b - a);
        const Vec3 u = normalize(cross(axis, std::abs(axis.y) < 0.9 ? Vec3{0, 1, 0} : Vec3{1, 0, 0}));
        const Vec3 v = cross(axis, u);
        MeshSurface* surfaces[2] = {&surf(partMaterial(mat, cand)), nullptr};
        if (!innerMat.empty()) surfaces[1] = &surf(partMaterial(innerMat, cand));
        constexpr std::uint32_t kNone = 0xffffffffu;
        std::vector<std::uint32_t> ring[2][2];
        for (auto& r : ring) for (auto& side : r) side.assign(static_cast<std::size_t>(segments) + 1, kNone);
        auto ringVertex = [&](int s, int end, int i) {
            auto& slot = ring[s][end][static_cast<std::size_t>(i)];
            if (slot == kNone) {
                const real angle = 2.0 * kPi * i / segments;
                const Vec3 p = (end == 0 ? a : b) + (u * std::cos(angle) + v * std::sin(angle)) * radius;
                slot = vertex(*surfaces[s], p, skinNearest(p, cand));
            }
            return slot;
        };
        for (int i = 0; i < segments; ++i) {
            const real mid = 2.0 * kPi * (i + 0.5) / segments;
            const Vec3 normal = u * std::cos(mid) + v * std::sin(mid);
            const int s = surfaces[1] && dot(normal, innerDir) > 0.0 ? 1 : 0;
            MeshSurface& m = *surfaces[s];
            tri(m, ringVertex(s, 0, i), ringVertex(s, 0, i + 1), ringVertex(s, 1, i + 1));
            tri(m, ringVertex(s, 0, i), ringVertex(s, 1, i + 1), ringVertex(s, 1, i));
        }
        // Separate cap vertices retain hard edges at the machined ends.
        MeshSurface& m = *surfaces[0];
        const auto ca = vertex(m, a, skinNearest(a, cand));
        const auto cb = vertex(m, b, skinNearest(b, cand));
        for (int i = 0; i < segments; ++i) {
            const real t0 = 2.0 * kPi * i / segments, t1 = 2.0 * kPi * (i + 1) / segments;
            const Vec3 o0 = (u * std::cos(t0) + v * std::sin(t0)) * radius;
            const Vec3 o1 = (u * std::cos(t1) + v * std::sin(t1)) * radius;
            tri(m, ca, vertex(m, a + o1, skinNearest(a + o1, cand)), vertex(m, a + o0, skinNearest(a + o0, cand)));
            tri(m, cb, vertex(m, b + o0, skinNearest(b + o0, cand)), vertex(m, b + o1, skinNearest(b + o1, cand)));
        }
    }

    /// Cylinder between nodes a and b (line skinned, oriented by ref).
    void strut(const std::string& mat, std::uint32_t a, std::uint32_t b, std::uint32_t ref, real radius,
               int seg = 8, real t0 = 0.0, real t1 = 1.0, real s0 = 0.0, real s1 = 0.0) {
        MeshSurface& m = surf(mat);
        const Vec3 pa = body_.positions()[a], pb = body_.positions()[b], pr = body_.positions()[ref];
        const Vec3 e1 = normalize(pb - pa);
        Vec3 e2 = pr - pa;
        e2 = normalize(e2 - e1 * dot(e2, e1));
        if (lengthSq(e2) < 1e-6) e2 = normalize(cross(e1, Vec3{0, 1, 0.3}));
        const Vec3 e3 = cross(e1, e2);
        std::vector<std::uint32_t> r0, r1;
        for (int i = 0; i < seg; ++i) {
            const real ang = 2.0 * kPi * i / seg;
            const Vec3 off = e2 * (radius * std::cos(ang)) + e3 * (radius * std::sin(ang));
            const Vec3 p0 = pa + (pb - pa) * t0 + e1 * s0 + off;
            const Vec3 p1 = pa + (pb - pa) * t1 + e1 * s1 + off;
            r0.push_back(vertex(m, p0, skinLine(p0, a, b, ref, t0, s0)));
            r1.push_back(vertex(m, p1, skinLine(p1, a, b, ref, t1, s1)));
        }
        for (int i = 0; i < seg; ++i) {
            const int j = (i + 1) % seg;
            tri(m, r0[static_cast<std::size_t>(i)], r0[static_cast<std::size_t>(j)], r1[static_cast<std::size_t>(j)]);
            tri(m, r0[static_cast<std::size_t>(i)], r1[static_cast<std::size_t>(j)], r1[static_cast<std::size_t>(i)]);
        }
    }

    /// Coil spring between a and b.
    void coil(const std::string& mat, std::uint32_t a, std::uint32_t b, std::uint32_t ref, real coilR, real wireR,
              real turns, real t0, real t1) {
        MeshSurface& m = surf(mat);
        const Vec3 pa = body_.positions()[a], pb = body_.positions()[b], pr = body_.positions()[ref];
        const Vec3 e1 = normalize(pb - pa);
        Vec3 e2 = normalize((pr - pa) - e1 * dot(pr - pa, e1));
        const Vec3 e3 = cross(e1, e2);
        const int steps = static_cast<int>(turns * 14);
        const int ring = 6;
        std::vector<std::uint32_t> prev;
        for (int i = 0; i <= steps; ++i) {
            const real u = static_cast<real>(i) / steps;
            const real ang = 2.0 * kPi * turns * u;
            const real t = t0 + (t1 - t0) * u;
            const Vec3 radial = e2 * std::cos(ang) + e3 * std::sin(ang);
            const Vec3 tangent = normalize(e1 * ((t1 - t0) * length(pb - pa)) + cross(e1, radial) * (2.0 * kPi * turns * coilR));
            const Vec3 nb = cross(tangent, radial);
            const Vec3 center = pa + (pb - pa) * t + radial * coilR;
            std::vector<std::uint32_t> cur;
            for (int k = 0; k < ring; ++k) {
                const real a2 = 2.0 * kPi * k / ring;
                const Vec3 p = center + radial * (wireR * std::cos(a2)) + nb * (wireR * std::sin(a2));
                cur.push_back(vertex(m, p, skinLine(p, a, b, ref, t, 0.0)));
            }
            if (!prev.empty())
                for (int k = 0; k < ring; ++k) {
                    const int j = (k + 1) % ring;
                    tri(m, prev[static_cast<std::size_t>(k)], cur[static_cast<std::size_t>(k)], cur[static_cast<std::size_t>(j)]);
                    tri(m, prev[static_cast<std::size_t>(k)], cur[static_cast<std::size_t>(j)], prev[static_cast<std::size_t>(j)]);
                }
            prev = cur;
        }
    }

private:
    const SoftBody& body_;
    CarVisual& vis_;
    const std::vector<float>& frames_;
    const CarLayout& layout_;
    std::map<std::pair<std::string, bool>, std::size_t> index_;
};

void computeNormals(const std::vector<float>& pos, const std::vector<std::uint32_t>& idx, std::vector<float>& nrm) {
    nrm.assign(pos.size(), 0.0f);
    for (std::size_t i = 0; i + 2 < idx.size(); i += 3) {
        const std::uint32_t a = idx[i], b = idx[i + 1], c = idx[i + 2];
        const float ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
        const float e1x = pos[b * 3] - ax, e1y = pos[b * 3 + 1] - ay, e1z = pos[b * 3 + 2] - az;
        const float e2x = pos[c * 3] - ax, e2y = pos[c * 3 + 1] - ay, e2z = pos[c * 3 + 2] - az;
        const float nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
        for (std::uint32_t v : {a, b, c}) {
            nrm[v * 3] += nx;
            nrm[v * 3 + 1] += ny;
            nrm[v * 3 + 2] += nz;
        }
    }
    for (std::size_t v = 0; v + 2 < nrm.size(); v += 3) {
        const float l = std::sqrt(nrm[v] * nrm[v] + nrm[v + 1] * nrm[v + 1] + nrm[v + 2] * nrm[v + 2]);
        if (l > 1e-12f) {
            nrm[v] /= l;
            nrm[v + 1] /= l;
            nrm[v + 2] /= l;
        } else {
            nrm[v + 1] = 1.0f;
        }
    }
}

// ---------------------------------------------------------------- wheel-local meshes
struct LocalMesh {
    MeshSurface* m;
    std::uint32_t v(const Vec3& p) {
        const auto idx = static_cast<std::uint32_t>(m->positions.size() / 3);
        m->positions.insert(m->positions.end(), {static_cast<float>(p.x), static_cast<float>(p.y), static_cast<float>(p.z)});
        m->normals.insert(m->normals.end(), {0.0f, 0.0f, 1.0f});
        return idx;
    }
    void t(std::uint32_t a, std::uint32_t b, std::uint32_t c) { m->indices.insert(m->indices.end(), {a, b, c}); }
    /// Revolve a (r, z) profile around local Z with outward-facing normals (profile ordered so that
    /// the surface faces away from the axis when walking from inner (-z) to outer (+z)).
    void revolve(const std::vector<std::pair<real, real>>& prof, int seg, bool flip = false) {
        const std::size_t np = prof.size();
        std::vector<std::uint32_t> ids;
        for (int s = 0; s <= seg; ++s) {
            const real a = 2.0 * kPi * s / seg;
            for (const auto& pr : prof) ids.push_back(v({pr.first * std::cos(a), pr.first * std::sin(a), pr.second}));
        }
        for (int s = 0; s < seg; ++s)
            for (std::size_t k = 0; k + 1 < np; ++k) {
                const std::uint32_t a = ids[static_cast<std::size_t>(s) * np + k], b = ids[static_cast<std::size_t>(s) * np + k + 1];
                const std::uint32_t c = ids[static_cast<std::size_t>(s + 1) * np + k], d = ids[static_cast<std::size_t>(s + 1) * np + k + 1];
                if (!flip) { t(a, c, d); t(a, d, b); }
                else { t(a, d, c); t(a, b, d); }
            }
    }
    /// A cast-alloy spoke at angle `a` round the wheel axis: tapered from the hub (r0, width w0, face
    /// height z0) to the rim (r1, w1, z1), with a crowned, bevelled face and a shallower back. The
    /// cross-section shares its vertices along the length so the crown shades smoothly.
    void spoke(real a, real r0, real r1, real z0, real z1, real w0, real w1, real thick) {
        const Vec3 dir{std::cos(a), std::sin(a), 0.0}, tan{-std::sin(a), std::cos(a), 0.0};
        // Cross-section (tangential factor of the half width, axial offset factor of the thickness).
        static const real cs[8][2] = {{-1.0, -0.9}, {-1.0, 0.25}, {-0.82, 0.78}, {-0.35, 1.0},
                                      {0.35, 1.0}, {0.82, 0.78}, {1.0, 0.25}, {1.0, -0.9}};
        const int steps = 6;
        std::vector<std::uint32_t> ids;
        std::vector<Vec3> pts;
        for (int i = 0; i <= steps; ++i) {
            const real u = static_cast<real>(i) / steps;
            const real r = r0 + (r1 - r0) * u;
            // A slight S along the face: it leaves the hub flat and dips into the rim bed.
            const real z = z0 + (z1 - z0) * (u * u * (3.0 - 2.0 * u));
            const real w = w0 + (w1 - w0) * u;
            for (const auto& c : cs) {
                const Vec3 p = dir * r + tan * (w * c[0]) + Vec3{0.0, 0.0, z + thick * c[1]};
                ids.push_back(v(p));
                pts.push_back(p);
            }
        }
        for (int i = 0; i < steps; ++i)
            for (int k = 0; k < 8; ++k) {
                const int k1 = (k + 1) % 8;
                const std::uint32_t a0 = ids[static_cast<std::size_t>(i * 8 + k)], a1 = ids[static_cast<std::size_t>(i * 8 + k1)];
                const std::uint32_t b0 = ids[static_cast<std::size_t>((i + 1) * 8 + k)], b1 = ids[static_cast<std::size_t>((i + 1) * 8 + k1)];
                // Face outward from the spoke's centre line.
                const Vec3 centre = dir * (r0 + (r1 - r0) * (i + 0.5) / steps) + Vec3{0.0, 0.0, z0 + (z1 - z0) * (i + 0.5) / steps};
                const Vec3 pa = pts[static_cast<std::size_t>(i * 8 + k)], pb = pts[static_cast<std::size_t>((i + 1) * 8 + k1)];
                const Vec3 n = cross(pts[static_cast<std::size_t>((i + 1) * 8 + k)] - pa, pts[static_cast<std::size_t>(i * 8 + k1)] - pa);
                if (dot(n, (pa + pb) * 0.5 - centre) >= 0) { t(a0, b0, b1); t(a0, b1, a1); }
                else { t(a0, b1, b0); t(a0, a1, b1); }
            }
    }
    void boxLocal(const Vec3& c, const Vec3& h, real rotZ) {
        const real cs = std::cos(rotZ), sn = std::sin(rotZ);
        auto rot = [&](const Vec3& p) { return Vec3{p.x * cs - p.y * sn, p.x * sn + p.y * cs, p.z}; };
        const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
        Vec3 cr[8];
        for (int i = 0; i < 8; ++i)
            cr[i] = rot(c + Vec3{h.x * ((i & 4) ? 1 : -1), h.y * ((i & 2) ? 1 : -1), h.z * ((i & 1) ? 1 : -1)});
        const Vec3 cc = rot(c);
        for (const auto& f : faces) {
            std::uint32_t q[4];
            for (int k = 0; k < 4; ++k) q[k] = v(cr[f[k]]);
            const Vec3 n = cross(cr[f[1]] - cr[f[0]], cr[f[2]] - cr[f[0]]);
            if (dot(n, (cr[f[0]] + cr[f[2]]) * 0.5 - cc) < 0) { t(q[0], q[2], q[1]); t(q[0], q[3], q[2]); }
            else { t(q[0], q[1], q[2]); t(q[0], q[2], q[3]); }
        }
    }
};

std::vector<MeshSurface> buildWheelMeshes(const TireDef& tire, BodyStyle style) {
    std::vector<MeshSurface> out(4);
    out[0].material = "tire";
    out[1].material = "rim";
    out[2].material = "brake_disc";
    out[3].material = "chrome";
    const real R = tire.radius, w = tire.width, Rr = tire.rimRadius;
    const real hwid = 0.5 * w;
    {
        LocalMesh lm{&out[0]};
        lm.revolve({{Rr + 0.006, -hwid * 0.90}, {Rr + 0.03, -hwid * 0.99}, {R - 0.05, -hwid * 1.03},
                    {R - 0.016, -hwid * 0.95}, {R - 0.002, -hwid * 0.78},
                    {R, -hwid * 0.63}, {R - 0.007, -hwid * 0.60}, {R - 0.007, -hwid * 0.51}, {R, -hwid * 0.48},
                    {R, -hwid * 0.23}, {R - 0.006, -hwid * 0.20}, {R - 0.006, -hwid * 0.12}, {R, -hwid * 0.09},
                    {R, hwid * 0.09}, {R - 0.006, hwid * 0.12}, {R - 0.006, hwid * 0.20}, {R, hwid * 0.23},
                    {R, hwid * 0.48}, {R - 0.007, hwid * 0.51}, {R - 0.007, hwid * 0.60}, {R, hwid * 0.63},
                    {R - 0.002, hwid * 0.78}, {R - 0.016, hwid * 0.95}, {R - 0.05, hwid * 1.03},
                    {Rr + 0.03, hwid * 0.99}, {Rr + 0.006, hwid * 0.90}},
                   56);
    }
    {
        LocalMesh lm{&out[1]};
        // Outer lip + dish, then inner barrel (faces the axis).
        lm.revolve({{Rr - 0.045, hwid * 0.60}, {Rr - 0.012, hwid * 0.86}, {Rr + 0.004, hwid * 0.92}, {Rr + 0.012, hwid * 0.86}},
                   48, true);
        lm.revolve({{Rr - 0.004, -hwid * 0.92}, {Rr - 0.004, hwid * 0.84}}, 48, true);
        // Match the rim design to the vehicle class.
        lm.revolve({{0.0, hwid * 0.74}, {0.072, hwid * 0.74}, {0.08, hwid * 0.55}}, 20, true);
        const int spokes = style == BodyStyle::SUV ? 6 : (style == BodyStyle::Sedan ? 8 : 5);
        const real spokeHalf = style == BodyStyle::SUV ? 0.031 : (style == BodyStyle::Sedan ? 0.016 : 0.023);
        const real rimEnd = Rr - 0.035;
        if (tire.rimDesign == "multispoke") {
            // Ten slim spokes in pairs: the usual larger sports rim.
            for (int s = 0; s < 5; ++s)
                for (real off : {-0.105, 0.105}) {
                    const real a = 2.0 * kPi * s / 5 + off;
                    lm.spoke(a, 0.062, rimEnd, hwid * 0.71, hwid * 0.58, 0.016, 0.0115, 0.014);
                }
        } else if (tire.rimDesign == "forged") {
            // Six broad, thin spokes in a deep concave: the hub stands far out, the spokes fall
            // steeply into the rim bed.
            for (int s = 0; s < 6; ++s)
                lm.spoke(2.0 * kPi * s / 6, 0.062, rimEnd, hwid * 0.76, hwid * 0.40, 0.027, 0.013, 0.010);
        } else if (tire.rimDesign == "steel") {
            // Pressed steel wheel: a closed dish with a stiffening ring and eight round vents
            // suggested by short bosses between them.
            lm.revolve({{0.07, hwid * 0.70}, {0.15, hwid * 0.68}, {0.16, hwid * 0.74}, {0.175, hwid * 0.68},
                        {rimEnd - 0.01, hwid * 0.60}, {rimEnd + 0.012, hwid * 0.52}}, 40, true);
            for (int s = 0; s < 8; ++s)
                lm.spoke(2.0 * kPi * (s + 0.5) / 8, 0.19, rimEnd - 0.012, hwid * 0.63, hwid * 0.60, 0.016, 0.016, 0.006);
        }
        for (int s = 0; s < spokes && tire.rimDesign.empty(); ++s) {
            const real a = 2.0 * kPi * s / spokes;
            // Wider at the hub, slimmer where it meets the rim bed; the face falls from the hub
            // towards the lip.
            lm.spoke(a, 0.066, Rr - 0.035, hwid * 0.70, hwid * 0.60, spokeHalf * 1.25, spokeHalf * 0.8, 0.015);
            if (style == BodyStyle::Coupe)
                lm.spoke(a + kPi / spokes, 0.066, Rr - 0.035, hwid * 0.70, hwid * 0.60, 0.013, 0.009, 0.013);
        }
    }
    {
        LocalMesh lm{&out[2]};
        const real dr = Rr - 0.035;
        lm.revolve({{0.06, -0.035}, {dr, -0.035}, {dr, -0.01}, {0.06, -0.01}}, 40);
        // Ventilation slots ring hint: darker inner hat.
        lm.revolve({{0.06, -0.005}, {0.11, -0.005}, {0.11, 0.03}, {0.0, 0.03}}, 24);
    }
    {
        LocalMesh lm{&out[3]};
        lm.revolve({{0.0, hwid * 0.80}, {0.032, hwid * 0.78}, {0.036, hwid * 0.74}}, 18, true);
        // Wheel nuts: hexagonal, each from three crossed flat bars.
        for (int s = 0; s < 5; ++s) {
            const real a = 2.0 * kPi * (s + 0.5) / 5;
            for (int k = 0; k < 3; ++k) {
                const real spin = kPi / 3.0 * k;
                const real cx = 0.052 * std::cos(a), cy = 0.052 * std::sin(a);
                // boxLocal rotates about the wheel axis: place the nut centre, then turn the bar.
                const real ca = std::cos(-spin), sa = std::sin(-spin);
                lm.boxLocal({cx * ca - cy * sa, cx * sa + cy * ca, hwid * 0.76}, {0.0095, 0.0055, 0.012}, spin);
            }
        }
    }
    for (MeshSurface& m : out) computeNormals(m.positions, m.indices, m.normals);
    return out;
}

}  // namespace

// ============================================================================== skinning runtime

namespace {
void cellBasis(const Vec3& fl, const Vec3& fr, const Vec3& rl, const Vec3& rr, Vec3& f, Vec3& r, Vec3& u) {
    f = normalize((fl + fr) - (rl + rr));
    const Vec3 r0 = (fr + rr) - (fl + rl);
    u = normalize(cross(r0, f));
    r = cross(f, u);
}
}  // namespace

void computeNodeFrames(const std::vector<Vec3>& pos, const CarVisual& vis, std::vector<float>& frames) {
    const std::size_t n = pos.size();
    frames.resize(12 + n * 3);
    // Rigid motion of the passenger cell: R = B_now * B_rest^T, t = c_now - R * c_rest.
    real R[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
    Vec3 t{0, 0, 0};
    const auto* fr = vis.frameRefs;
    // Nodes fitted after the build (a tow bar) sit beyond the rest list and are left out.
    const std::size_t nr = vis.restNodes.size();
    if (nr != 0 && nr <= n && fr[0] < nr && fr[1] < nr && fr[2] < nr && fr[3] < nr) {
        Vec3 f0, r0, u0, f1, r1, u1;
        cellBasis(vis.restNodes[fr[0]], vis.restNodes[fr[1]], vis.restNodes[fr[2]], vis.restNodes[fr[3]], f0, r0, u0);
        cellBasis(pos[fr[0]], pos[fr[1]], pos[fr[2]], pos[fr[3]], f1, r1, u1);
        const Vec3 b0[3] = {f0, r0, u0}, b1[3] = {f1, r1, u1};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j) R[i][j] = b1[0][i] * b0[0][j] + b1[1][i] * b0[1][j] + b1[2][i] * b0[2][j];
        const Vec3 c0 = (vis.restNodes[fr[0]] + vis.restNodes[fr[1]] + vis.restNodes[fr[2]] + vis.restNodes[fr[3]]) * 0.25;
        const Vec3 c1 = (pos[fr[0]] + pos[fr[1]] + pos[fr[2]] + pos[fr[3]]) * 0.25;
        t = c1 - Vec3{R[0][0] * c0.x + R[0][1] * c0.y + R[0][2] * c0.z, R[1][0] * c0.x + R[1][1] * c0.y + R[1][2] * c0.z,
                      R[2][0] * c0.x + R[2][1] * c0.y + R[2][2] * c0.z};
    }
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) frames[static_cast<std::size_t>(i * 3 + j)] = static_cast<float>(R[i][j]);
    frames[9] = static_cast<float>(t.x);
    frames[10] = static_cast<float>(t.y);
    frames[11] = static_cast<float>(t.z);
    const bool haveRest = nr != 0 && nr <= n;
    // Rigid part frames (bonnet, doors, bumpers): best-fit rotation of each part's nodes, extracted
    // with the iterative method of Mueller et al. 2016 (warm-started from the previous frame), so a
    // panel swinging on its hinges or lying loose on the road keeps its shape.
    const std::size_t partBase = 12 + n * 3;
    const std::size_t nParts = haveRest ? vis.parts.size() : 0;
    std::vector<float> previous;
    if (frames.size() == partBase + 16 * nParts) previous.assign(frames.begin() + static_cast<std::ptrdiff_t>(partBase), frames.end());
    frames.resize(partBase + 16 * nParts);
    for (std::size_t p = 0; p < nParts; ++p) {
        const auto& nodes = vis.parts[p];
        float* out = &frames[partBase + 16 * p];
        Vec3 c0{}, c1{};
        for (auto k : nodes) { c0 += vis.restNodes[k]; c1 += pos[k]; }
        const real inv = nodes.empty() ? 0.0 : 1.0 / static_cast<real>(nodes.size());
        c0 = c0 * inv;
        c1 = c1 * inv;
        real A[3][3] = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}};  // sum (now - c1) (rest - c0)^T
        for (auto k : nodes) {
            const Vec3 a = pos[k] - c1, b = vis.restNodes[k] - c0;
            const real av[3] = {a.x, a.y, a.z}, bv[3] = {b.x, b.y, b.z};
            for (int i = 0; i < 3; ++i)
                for (int j = 0; j < 3; ++j) A[i][j] += av[i] * bv[j];
        }
        real q[4] = {1, 0, 0, 0};  // w, x, y, z
        if (!previous.empty()) for (int i = 0; i < 4; ++i) q[i] = previous[16 * p + 12 + static_cast<std::size_t>(i)];
        else {
            // Start from the passenger cell so the first fit converges to the right branch.
            const real tr = R[0][0] + R[1][1] + R[2][2];
            q[0] = std::sqrt(std::max<real>(0.0, 1.0 + tr)) * 0.5;
            const real s4 = q[0] > 1e-6 ? 0.25 / q[0] : 0.0;
            q[1] = (R[2][1] - R[1][2]) * s4; q[2] = (R[0][2] - R[2][0]) * s4; q[3] = (R[1][0] - R[0][1]) * s4;
        }
        real Rp[3][3];
        for (int it = 0; it < 12; ++it) {
            const real w = q[0], x = q[1], y = q[2], z = q[3];
            Rp[0][0] = 1 - 2 * (y * y + z * z); Rp[0][1] = 2 * (x * y - z * w); Rp[0][2] = 2 * (x * z + y * w);
            Rp[1][0] = 2 * (x * y + z * w); Rp[1][1] = 1 - 2 * (x * x + z * z); Rp[1][2] = 2 * (y * z - x * w);
            Rp[2][0] = 2 * (x * z - y * w); Rp[2][1] = 2 * (y * z + x * w); Rp[2][2] = 1 - 2 * (x * x + y * y);
            Vec3 omega{}; real dotSum = 0;
            for (int col = 0; col < 3; ++col) {
                const Vec3 r{Rp[0][col], Rp[1][col], Rp[2][col]}, a{A[0][col], A[1][col], A[2][col]};
                omega += cross(r, a);
                dotSum += dot(r, a);
            }
            omega = omega * (1.0 / (std::abs(dotSum) + 1e-9));
            const real angle = length(omega);
            if (angle < 1e-9) break;
            const Vec3 axis = omega / angle;
            const real h = 0.5 * angle, sh = std::sin(h);
            const real dq[4] = {std::cos(h), axis.x * sh, axis.y * sh, axis.z * sh};
            const real nq[4] = {dq[0] * q[0] - dq[1] * q[1] - dq[2] * q[2] - dq[3] * q[3],
                                dq[0] * q[1] + dq[1] * q[0] + dq[2] * q[3] - dq[3] * q[2],
                                dq[0] * q[2] - dq[1] * q[3] + dq[2] * q[0] + dq[3] * q[1],
                                dq[0] * q[3] + dq[1] * q[2] - dq[2] * q[1] + dq[3] * q[0]};
            const real nl = std::sqrt(nq[0] * nq[0] + nq[1] * nq[1] + nq[2] * nq[2] + nq[3] * nq[3]);
            for (int i = 0; i < 4; ++i) q[i] = nq[i] / nl;
        }
        {
            const real w = q[0], x = q[1], y = q[2], z = q[3];
            Rp[0][0] = 1 - 2 * (y * y + z * z); Rp[0][1] = 2 * (x * y - z * w); Rp[0][2] = 2 * (x * z + y * w);
            Rp[1][0] = 2 * (x * y + z * w); Rp[1][1] = 1 - 2 * (x * x + z * z); Rp[1][2] = 2 * (y * z - x * w);
            Rp[2][0] = 2 * (x * z - y * w); Rp[2][1] = 2 * (y * z + x * w); Rp[2][2] = 1 - 2 * (x * x + y * y);
        }
        const Vec3 tp = c1 - Vec3{Rp[0][0] * c0.x + Rp[0][1] * c0.y + Rp[0][2] * c0.z, Rp[1][0] * c0.x + Rp[1][1] * c0.y + Rp[1][2] * c0.z,
                                  Rp[2][0] * c0.x + Rp[2][1] * c0.y + Rp[2][2] * c0.z};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j) out[i * 3 + j] = static_cast<float>(Rp[i][j]);
        out[9] = static_cast<float>(tp.x); out[10] = static_cast<float>(tp.y); out[11] = static_cast<float>(tp.z);
        for (int i = 0; i < 4; ++i) out[12 + i] = static_cast<float>(q[i]);
    }
    for (std::size_t k = 0; k < n; ++k) {
        Vec3 d{0, 0, 0};
        if (haveRest && k < nr) {
            const Vec3& q = vis.restNodes[k];
            const std::int32_t part = k < vis.nodePart.size() ? vis.nodePart[k] : -1;
            const float* F = part >= 0 && static_cast<std::size_t>(part) < nParts ? &frames[partBase + 16 * static_cast<std::size_t>(part)] : frames.data();
            const Vec3 rigid{F[0] * q.x + F[1] * q.y + F[2] * q.z + F[9], F[3] * q.x + F[4] * q.y + F[5] * q.z + F[10],
                             F[6] * q.x + F[7] * q.y + F[8] * q.z + F[11]};
            d = pos[k] - rigid;
        }
        frames[12 + k * 3] = static_cast<float>(d.x);
        frames[12 + k * 3 + 1] = static_cast<float>(d.y);
        frames[12 + k * 3 + 2] = static_cast<float>(d.z);
    }
}

const float* skinFrame(const std::vector<float>& frames, std::size_t nodeCount, std::int32_t part) {
    const std::size_t at = 12 + nodeCount * 3 + 16 * static_cast<std::size_t>(std::max(part, 0));
    return part >= 0 && at + 12 <= frames.size() ? &frames[at] : frames.data();
}

void setRigidParts(CarVisual& vis, const std::vector<std::vector<std::uint32_t>>& parts) {
    vis.parts.clear();
    vis.nodePart.assign(vis.restNodes.size(), -1);
    for (const auto& nodes : parts) {
        if (nodes.size() < 4) continue;
        const auto index = static_cast<std::int32_t>(vis.parts.size());
        vis.parts.push_back(nodes);
        for (auto k : nodes)
            if (k < vis.nodePart.size()) vis.nodePart[k] = index;
    }
    for (auto& surf : vis.skinned) tagRigidPartVertices(vis, surf);
}

void tagRigidPartVertices(const CarVisual& vis, MeshSurface& surf) {
    for (auto& sk : surf.skin) {
        sk.part = -1;
        if (sk.weight[0] < 0.0f || vis.nodePart.empty()) continue;
        std::int32_t part = -2;
        for (int k = 0; k < 4; ++k) {
            if (sk.weight[k] <= 0.0f) continue;
            const std::int32_t pk = sk.node[k] < vis.nodePart.size() ? vis.nodePart[sk.node[k]] : -1;
            if (part == -2) part = pk;
            else if (part != pk) { part = -1; break; }
        }
        sk.part = part >= 0 ? part : -1;
    }
}

Vec3 evalSkin(const std::vector<Vec3>& pos, const std::vector<float>& frames, const VertexSkin& s) {
    if (s.weight[0] < 0.0f) {  // line skin
        const Vec3 pa = pos[s.node[0]], pb = pos[s.node[1]], pr = pos[s.node[2]];
        Vec3 d = pb - pa;
        const real len = length(d);
        const Vec3 e1 = len > 1e-9 ? d / len : Vec3{1, 0, 0};
        Vec3 e2 = pr - pa;
        e2 = e2 - e1 * dot(e2, e1);
        const real l2 = length(e2);
        e2 = l2 > 1e-9 ? e2 / l2 : Vec3{0, 1, 0};
        const Vec3 e3 = cross(e1, e2);
        return pa + d * s.weight[1] + e1 * s.weight[2] + e2 * s.local[0][0] + e3 * s.local[0][1];
    }
    const float* R = skinFrame(frames, pos.size(), s.part);
    const float x = s.local[0][0], y = s.local[0][1], z = s.local[0][2];
    Vec3 out{R[0] * x + R[1] * y + R[2] * z + R[9], R[3] * x + R[4] * y + R[5] * z + R[10], R[6] * x + R[7] * y + R[8] * z + R[11]};
    for (int k = 0; k < 4; ++k) {
        const float w = s.weight[k];
        if (w <= 0.0f) continue;
        const float* d = &frames[12 + static_cast<std::size_t>(s.node[k]) * 3];
        out.x += w * d[0];
        out.y += w * d[1];
        out.z += w * d[2];
    }
    return out;
}

void deformSurface(const std::vector<Vec3>& pos, const std::vector<float>& frames, const MeshSurface& surf,
                   std::vector<float>& outPositions, std::vector<float>& outNormals) {
    const std::size_t nv = surf.skin.size();
    outPositions.resize(nv * 3);
    for (std::size_t i = 0; i < nv; ++i) {
        const Vec3 p = evalSkin(pos, frames, surf.skin[i]);
        outPositions[i * 3] = static_cast<float>(p.x);
        outPositions[i * 3 + 1] = static_cast<float>(p.y);
        outPositions[i * 3 + 2] = static_cast<float>(p.z);
    }
    computeNormals(outPositions, surf.indices, outNormals);
}

VertexSkin bindToNodes(const std::vector<Vec3>& nodes, const std::vector<std::uint32_t>& candidates, const Vec3& p) {
    std::array<std::pair<real, std::uint32_t>, 4> best;
    best.fill({1e30, 0});
    for (std::uint32_t c : candidates) {
        const real d = lengthSq(nodes[c] - p);
        if (d < best[3].first) {
            best[3] = {d, c};
            std::sort(best.begin(), best.end());
        }
    }
    VertexSkin s;
    real wsum = 0;
    const std::size_t kk = std::min<std::size_t>(4, candidates.size());
    for (std::size_t i = 0; i < kk; ++i) {
        const real d = std::sqrt(best[i].first);
        const real w = 1.0 / ((d + 0.08) * (d + 0.08));
        s.node[i] = best[i].second;
        s.weight[i] = static_cast<float>(w);
        wsum += w;
    }
    for (std::size_t i = 0; i < kk; ++i) s.weight[i] = static_cast<float>(s.weight[i] / wsum);
    s.local[0][0] = static_cast<float>(p.x);
    s.local[0][1] = static_cast<float>(p.y);
    s.local[0][2] = static_cast<float>(p.z);
    return s;
}

void deformSurfaceBlended(const std::vector<Vec3>& pos, const std::vector<float>& frames, const MeshSurface& surf,
                          std::vector<float>& outPositions, std::vector<float>& outNormals) {
    const std::size_t nv = surf.skin.size();
    outPositions.resize(nv * 3);
    std::vector<float> dent(nv, 0.0f);
    bool anyDent = false;
    for (std::size_t i = 0; i < nv; ++i) {
        const VertexSkin& sk = surf.skin[i];
        const Vec3 p = evalSkin(pos, frames, sk);
        outPositions[i * 3] = static_cast<float>(p.x);
        outPositions[i * 3 + 1] = static_cast<float>(p.y);
        outPositions[i * 3 + 2] = static_cast<float>(p.z);
        if (sk.weight[0] >= 0.0f) {
            // Local strain: how differently the bound nodes moved (a uniform sag is not a dent).
            float ax = 0, ay = 0, az = 0;
            for (int k = 0; k < 4; ++k) {
                if (sk.weight[k] <= 0.0f) continue;
                const float* d = &frames[12 + static_cast<std::size_t>(sk.node[k]) * 3];
                ax += sk.weight[k] * d[0];
                ay += sk.weight[k] * d[1];
                az += sk.weight[k] * d[2];
            }
            float spread = 0.0f;
            for (int k = 0; k < 4; ++k) {
                if (sk.weight[k] <= 0.0f) continue;
                const float* d = &frames[12 + static_cast<std::size_t>(sk.node[k]) * 3];
                const float ex = d[0] - ax, ey = d[1] - ay, ez = d[2] - az;
                spread = std::max(spread, std::sqrt(ex * ex + ey * ey + ez * ez));
            }
            dent[i] = std::clamp((spread - 0.02f) / 0.05f, 0.0f, 1.0f);
            if (dent[i] > 0.0f) anyDent = true;
        }
    }
    std::vector<float> geo;
    if (anyDent) computeNormals(outPositions, surf.indices, geo);
    outNormals.resize(nv * 3);
    for (std::size_t i = 0; i < nv; ++i) {
        const float nx = surf.normals[i * 3], ny = surf.normals[i * 3 + 1], nz = surf.normals[i * 3 + 2];
        const float* R = skinFrame(frames, pos.size(), surf.skin[i].part);
        float rx = R[0] * nx + R[1] * ny + R[2] * nz;
        float ry = R[3] * nx + R[4] * ny + R[5] * nz;
        float rz = R[6] * nx + R[7] * ny + R[8] * nz;
        if (anyDent && dent[i] > 0.0f) {
            const float t = dent[i];
            float gx = geo[i * 3], gy = geo[i * 3 + 1], gz = geo[i * 3 + 2];
            // Imported meshes may have mirrored parts / either winding: keep the rest normal's side.
            if (gx * rx + gy * ry + gz * rz < 0.0f) {
                gx = -gx;
                gy = -gy;
                gz = -gz;
            }
            rx += (gx - rx) * t;
            ry += (gy - ry) * t;
            rz += (gz - rz) * t;
        }
        const float l = std::sqrt(rx * rx + ry * ry + rz * rz);
        const float inv = l > 1e-8f ? 1.0f / l : 0.0f;
        outNormals[i * 3] = rx * inv;
        outNormals[i * 3 + 1] = ry * inv;
        outNormals[i * 3 + 2] = rz * inv;
    }
}

// ============================================================================== visual generation

void buildCarVisual(CarBuild& build, const Profile& prof, const CarRig& rig) {
    const SoftBody& body = build.body;
    CarVisual& vis = build.visual;
    const CarBodyDef& bd = build.def.body;

    vis.restNodes = body.positions();
    vis.frameRefs[0] = build.layout.refFL;
    vis.frameRefs[1] = build.layout.refFR;
    vis.frameRefs[2] = build.layout.refRL;
    vis.frameRefs[3] = build.layout.refRR;
    std::vector<float> frames;
    computeNodeFrames(body, vis, frames);
    VisBuilder vb(body, vis, frames, build.layout);

    const real L = prof.L;
    const real hw = prof.hw;
    const std::vector<std::uint32_t>& bodyNodes = rig.bodyNodes;
    const auto& frontNodes = bd.detachableBumpers ? build.layout.frontBumperNodes : bodyNodes;
    const auto& rearNodes = bd.detachableBumpers ? build.layout.rearBumperNodes : bodyNodes;
    auto bumperMaterial = [&](const std::string& material, real x, real y) {
        if (bd.detachableBumpers && x > L - 0.30 && y < bd.noseHeight - 0.16) return "bumper_front_" + material;
        if (bd.detachableBumpers && x < 0.30 && y < bd.tailHeight - 0.28) return "bumper_rear_" + material;
        return material;
    };
    auto surfaceNodes = [&](const std::string& material) -> const std::vector<std::uint32_t>& {
        if (material.rfind("bumper_front_", 0) == 0) return frontNodes;
        if (material.rfind("bumper_rear_", 0) == 0) return rearNodes;
        if (material.rfind("door_left_", 0) == 0) return build.layout.frontDoors[0].nodes;
        if (material.rfind("door_right_", 0) == 0) return build.layout.frontDoors[1].nodes;
        if (material.rfind("rdoor_left_", 0) == 0) return build.layout.rearDoors[0].nodes;
        if (material.rfind("rdoor_right_", 0) == 0) return build.layout.rearDoors[1].nodes;
        if (material.rfind("tailgate_", 0) == 0) return build.layout.tailgateNodes;
        return bodyNodes;
    };
    // Rear lid (tailgate / boot lid): the deck and rear window ahead of the latch line up to the
    // hinge, and the whole rear face above the latch, so its shut lines run along the rear corners.
    const auto& lidNodes = build.layout.tailgateNodes.size() == 8 ? build.layout.tailgateNodes : bodyNodes;
    const bool hasLid = build.layout.tailgateNodes.size() == 8;
    const real lidHingeX = hasLid ? 0.5 * (body.positions()[lidNodes[4]].x + body.positions()[lidNodes[0]].x) : -1.0;
    const real lidLatchY = hasLid ? 0.5 * (body.positions()[lidNodes[6]].y + body.positions()[lidNodes[2]].y) : 1e9;
    auto lidMaterial = [&](const std::string& material, real x, int seg) {
        if (hasLid && seg >= 8 && x < lidHingeX - 0.005 && material.rfind("bumper_", 0) != 0) return "tailgate_" + material;
        return material;
    };
    auto doorMaterial = [&](const std::string& material, real x, int seg, int side) {
        const auto& door = build.layout.frontDoors[static_cast<std::size_t>(side)];
        if (!door.nodes.empty() && x > door.rearX && x < door.frontX && seg >= 4 && seg <= 7)
            return std::string(side == 0 ? "door_left_" : "door_right_") + material;
        const auto& rear = build.layout.rearDoors[static_cast<std::size_t>(side)];
        if (!rear.nodes.empty() && x > rear.rearX && x < rear.frontX && seg >= 4 && seg <= 7)
            return std::string(side == 0 ? "rdoor_left_" : "rdoor_right_") + material;
        return material;
    };

    // ---- visual stations
    std::vector<real> xs;
    {
        std::vector<real> keys = {prof.xCowl, prof.xWsTop, prof.xRwTop, prof.xRwBase, 0.30, L - 0.30, prof.xCowl + 0.025, L - 0.12, L - 0.22, L - 0.30, 0.20, 0.25};
        for (real xa : {prof.xFA, prof.xRA})
            for (real d : {-prof.Ra - 0.003, -prof.Ra + 0.003, prof.Ra - 0.003, prof.Ra + 0.003}) keys.push_back(xa + d);
        for (real seam : {prof.xFD0, prof.xB, prof.xRD1})
            for (real d : {-0.004, 0.004}) keys.push_back(seam + d);
        const real handleF = prof.xB - 0.06;
        for (real d : {-0.10, 0.0}) keys.push_back(handleF + d);
        if (bd.doors >= 4) for (real d : {-0.10, 0.0}) keys.push_back(prof.xRD1 + 0.20 + d);
        real x = 0.0;
        while (x < L) {
            xs.push_back(x);
            const bool nearEnd = x < bd.cornerRadiusRear + 0.02 || x > L - bd.cornerRadiusFront - 0.02;
            x += nearEnd ? 0.014 : 0.035;
        }
        xs.push_back(L);
        for (real k : keys) if (k > 0.0 && k < L) xs.push_back(k);
        std::sort(xs.begin(), xs.end());
        std::vector<real> d;
        for (real v : xs) if (d.empty() || v - d.back() > 0.0025) d.push_back(v);
        xs = d;
        // Preserve these exact cuts even when the regular tessellation is nearby.
        for (const DoorLayout* doorPtr : {&build.layout.frontDoors[0], &build.layout.frontDoors[1], &build.layout.rearDoors[0], &build.layout.rearDoors[1]})
            if (!doorPtr->nodes.empty()) {
            const DoorLayout& door = *doorPtr;
            for (real edge : {door.rearX, door.frontX}) {
                xs.erase(std::remove_if(xs.begin(), xs.end(), [&](real sampleX) { return std::abs(sampleX - edge) < 0.0025; }), xs.end());
                xs.push_back(edge);
            }
        }
        std::sort(xs.begin(), xs.end());
        xs.erase(std::unique(xs.begin(), xs.end()), xs.end());
    }

    // ---- section sampling
    const int subdiv[10] = {3, 2, 3, 2, 4, 6, 1, 4, 3, 4};
    int K = 0;
    for (int s : subdiv) K += s;
    std::vector<int> segOf(static_cast<std::size_t>(K));
    {
        int k = 0;
        for (int s = 0; s < 10; ++s)
            for (int j = 0; j < subdiv[s]; ++j) segOf[static_cast<std::size_t>(k++)] = s;
    }
    auto samples = [&](real x) {
        Section sec = prof.section(x);
        // The roof is a pressed panel, not a flat extrusion: crown its centre
        // gently and roll the shoulder into the window header.
        if (x > prof.xRwTop && x < prof.xWsTop) {
            const real u = (x - prof.xRwTop) / (prof.xWsTop - prof.xRwTop);
            const real crown = 0.028 * std::sin(kPi * u);
            sec.y[8] -= crown * 0.22;
            sec.y[9] += crown * 0.65;
            sec.y[10] += crown;
        }
        std::vector<std::pair<real, real>> out;
        auto P = [&](int i) -> std::pair<real, real> {
            if (i < 3) return {sec.z[3], sec.y[3]};
            if (i > 10) return {-sec.z[9], sec.y[9]};
            return {sec.z[static_cast<std::size_t>(i)], sec.y[static_cast<std::size_t>(i)]};
        };
        for (int s = 0; s < 10; ++s) {
            for (int j = 0; j < subdiv[s]; ++j) {
                const real t = static_cast<real>(j) / subdiv[s];
                if (s < 3) {
                    const real z = lerp(sec.z[static_cast<std::size_t>(s)], sec.z[static_cast<std::size_t>(s + 1)], t);
                    const real y = lerp(sec.y[static_cast<std::size_t>(s)], sec.y[static_cast<std::size_t>(s + 1)], t);
                    out.push_back({z, y});
                } else {
                    const auto p0 = P(s - 1), p1 = P(s), p2 = P(s + 1), p3 = P(s + 2);
                    const real t2 = t * t, t3 = t2 * t;
                    auto cr = [&](real a, real b, real c, real d) {
                        return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
                    };
                    out.push_back({std::max<real>(0.0, cr(p0.first, p1.first, p2.first, p3.first)),
                                   cr(p0.second, p1.second, p2.second, p3.second)});
                }
            }
        }
        out.push_back({0.0, sec.y[10]});
        return out;
    };

    const real cPillar = bd.style == BodyStyle::Coupe ? 0.34 : (bd.style == BodyStyle::Sedan ? 0.24 : (bd.style == BodyStyle::SUV ? 0.18 : 0.28));
    const real handleF = prof.xB - 0.06;
    const real handleR = prof.xRD1 + 0.20;
    auto quadMaterial = [&](real xm, real ym, real /*zm*/, int seg) -> std::string {
        const real yB = prof.yBottom(xm);
        const real yBe = prof.yBelt(xm);
        const bool gh = prof.greenhouse(xm) > 0.04;
        if (seg == 0) return "underbody";
        if (seg <= 2) return prof.archY(xm) > 0.0 ? "arch_liner" : "trim";
        if (seg <= 5) {
            if (xm > L - 0.40 && ym < yB + 0.13) return "trim";
            if (xm < 0.32 && ym < yB + 0.15) return "trim";
            // SUV cladding: only the sill band, not the whole lower half of the side.
            if (bd.style == BodyStyle::SUV && seg <= 3) return "trim";
            // (The black arch flares are their own mesh, see below: grid cells gave them a stepped edge.)
            const bool inDoorBand = ym > prof.ySill(xm) + 0.02 && ym < yBe - 0.015;
            for (real seam : {prof.xFD0, prof.xB, prof.xRD1})
                if (std::abs(xm - seam) < 0.004 && inDoorBand && (bd.doors >= 4 || seam != prof.xRD1)) return "seam";
            if (ym > yBe - 0.10 && ym < yBe - 0.055) {
                if (build.layout.frontDoors[0].nodes.empty() && xm > handleF - 0.10 && xm < handleF) return "chrome";
                if (bd.doors >= 4 && build.layout.rearDoors[0].nodes.empty() && xm > handleR - 0.10 && xm < handleR) return "chrome";
            }
            return "paint";
        }
        if (seg == 6) return gh ? "trim" : "paint";
        if (seg == 7) {
            if (!gh) return "paint";
            const bool frontWin = xm > prof.xB + 0.045 && xm < prof.xCowl - 0.09;
            const bool rearWin = xm > prof.xRwBase + cPillar && xm < prof.xB - 0.045;
            if (frontWin || rearWin) return "glass";
            if (std::abs(xm - prof.xB) <= 0.045) return "trim";
            return "paint";
        }
        // Independent bonnet surfaces follow the breakable panel, including its underside.
        if (build.layout.bonnetNodes.size() == 8 && xm > prof.xCowl + 0.025 && xm < L - 0.12) return "bonnet";
        // seg 8, 9: roof / windshield / rear window / hood / deck
        if (xm > prof.xWsTop + 0.035 && xm < prof.xCowl - 0.01) return "glass";
        if (xm > prof.xRwBase + 0.02 && xm < prof.xRwTop - 0.035) return "glass";
        return "paint";
    };

    // Vertex cache: key (station, side or centre, sample, material, interior)
    std::map<std::tuple<std::size_t, int, int, std::string>, std::uint32_t> cache;
    auto gridVertex = [&](std::size_t si, int side, int k, const std::string& mat, const std::vector<std::vector<std::pair<real, real>>>& smp) {
        const int sideKey = (k == 0 || k == K) ? 2 : side;
        auto key = std::make_tuple(si, sideKey, k, mat);
        auto it = cache.find(key);
        if (it != cache.end()) return it->second;
        const auto& pz = smp[si][static_cast<std::size_t>(k)];
        Vec3 p{xs[si], pz.second, side == 0 ? -pz.first : pz.first};
        if (mat == "door_left_interior" || mat == "door_right_interior" || mat == "rdoor_left_interior" || mat == "rdoor_right_interior") {
            const auto& nodes = (mat[0] == 'r' ? build.layout.rearDoors : build.layout.frontDoors)[static_cast<std::size_t>(side)].nodes;
            const real thickness = std::abs(body.positions()[nodes[0]].z - body.positions()[nodes[1]].z);
            p.z -= (side == 0 ? -1.0 : 1.0) * thickness;
        }
        MeshSurface& m = vb.surf(mat);
        VertexSkin binding = vb.skinNearest(p, surfaceNodes(mat));
        if (mat == "bonnet" || mat == "bonnet_inner") {
            const auto& nodes = build.layout.bonnetNodes;
            const auto rear = nodes[side == 0 ? 4 : 5];
            const auto front = nodes[side == 0 ? 6 : 7];
            const auto across = nodes[side == 0 ? 5 : 4];
            const Vec3 delta = body.positions()[front] - body.positions()[rear];
            const real t = dot(p - body.positions()[rear], delta) / lengthSq(delta);
            binding = vb.skinLine(p, rear, front, across, t, 0.0);
        }
        const std::uint32_t v = vb.vertex(m, p, binding);
        cache[key] = v;
        return v;
    };

    std::vector<std::vector<std::pair<real, real>>> smp(xs.size());
    for (std::size_t i = 0; i < xs.size(); ++i) smp[i] = samples(xs[i]);

    for (std::size_t i = 0; i + 1 < xs.size(); ++i) {
        for (int side = 0; side < 2; ++side) {
            for (int k = 0; k < K; ++k) {
                const auto& a = smp[i][static_cast<std::size_t>(k)];
                const auto& b = smp[i + 1][static_cast<std::size_t>(k + 1)];
                const real xm = 0.5 * (xs[i] + xs[i + 1]);
                const real ym = 0.5 * (a.second + b.second);
                const real zm = 0.5 * (a.first + b.first) * (side ? 1.0 : -1.0);
                const int seg = segOf[static_cast<std::size_t>(k)];
                const std::string mat = lidMaterial(doorMaterial(bumperMaterial(quadMaterial(xm, ym, zm, seg), xm, ym), xm, seg, side), xm, seg);
                for (int pass = 0; pass < 2; ++pass) {
                    if (pass == 1 && (mat == "glass" || mat == "door_left_glass" || mat == "door_right_glass" || mat == "rdoor_left_glass" ||
                                      mat == "rdoor_right_glass" || mat == "tailgate_glass" || mat == "headlight" || mat == "taillight" || mat == "reverselight" || seg == 0)) continue;
                    const std::string mm = pass == 0 ? mat : (mat == "bonnet" ? "bonnet_inner" : mat.rfind("tailgate_", 0) == 0 ? "tailgate_interior"
                                                                 : doorMaterial(bumperMaterial("interior", xm, ym), xm, seg, side));
                    MeshSurface& m = vb.surf(mm);
                    const std::uint32_t v00 = gridVertex(i, side, k, mm, smp), v10 = gridVertex(i + 1, side, k, mm, smp);
                    const std::uint32_t v11 = gridVertex(i + 1, side, k + 1, mm, smp), v01 = gridVertex(i, side, k + 1, mm, smp);
                    const bool flip = (side == 0) != (pass == 1);
                    if (!flip) {
                        VisBuilder::tri(m, v00, v10, v11);
                        VisBuilder::tri(m, v00, v11, v01);
                    } else {
                        VisBuilder::tri(m, v00, v11, v10);
                        VisBuilder::tri(m, v00, v01, v11);
                    }
                }
            }
        }
    }

    // SUV: moulded plastic flares round the wheel arches, a band that follows the arch circle and
    // stands proud of the paint with a rounded outer face and a return into the opening.
    if (bd.style == BodyStyle::SUV) {
        MeshSurface& fm = vb.surf("trim");
        const auto& trimNodes = surfaceNodes("trim");
        auto sideZ = [&](real x, real y) {
            const auto sm = samples(x);
            for (std::size_t k = 0; k + 1 < sm.size(); ++k) {
                const int sg = segOf[std::min<std::size_t>(k, segOf.size() - 1)];
                if (sg < 3 || sg > 6) continue;
                const real y0 = sm[k].second, y1 = sm[k + 1].second;
                if ((y >= y0 && y <= y1) || (y <= y0 && y >= y1)) {
                    const real u = std::abs(y1 - y0) > 1e-6 ? (y - y0) / (y1 - y0) : 0.0;
                    return lerp(sm[k].first, sm[k + 1].first, u);
                }
            }
            return prof.halfW(x);
        };
        // Radial profile of the band: (radius offset from the arch, outward offset from the paint).
        static const real band[5][2] = {{0.0, -0.004}, {0.0, 0.020}, {0.022, 0.027}, {0.055, 0.022}, {0.082, 0.004}};
        const int steps = 36;
        for (real xa : {prof.xFA, prof.xRA}) {
            // The band ends where the arch meets the body's lower edge (higher of its two sides).
            const real yb = std::max(prof.yBottom(xa - prof.Ra), prof.yBottom(xa + prof.Ra)) + 0.01;
            const real th0 = std::asin(std::clamp((yb - prof.hubY) / prof.Ra, -1.0, 1.0));
            for (int side = 0; side < 2; ++side) {
                const real sz = side == 0 ? -1.0 : 1.0;
                std::vector<std::uint32_t> ids;
                for (int i = 0; i <= steps; ++i) {
                    const real th = th0 + (kPi - 2.0 * th0) * i / steps;
                    for (const auto& b : band) {
                        const real r = prof.Ra + b[0];
                        const real x = xa + r * std::cos(th);
                        const real y = std::max(std::max(yb, prof.yBottom(x) + 0.01), prof.hubY + r * std::sin(th));
                        const Vec3 p{x, y, sz * (sideZ(x, y) + b[1])};
                        ids.push_back(vb.vertex(fm, p, vb.skinNearest(p, trimNodes)));
                    }
                }
                for (int i = 0; i < steps; ++i)
                    for (int k = 0; k < 4; ++k) {
                        const std::uint32_t a = ids[static_cast<std::size_t>(i * 5 + k)], b = ids[static_cast<std::size_t>(i * 5 + k + 1)];
                        const std::uint32_t c = ids[static_cast<std::size_t>((i + 1) * 5 + k)], d = ids[static_cast<std::size_t>((i + 1) * 5 + k + 1)];
                        const Vec3 pa{fm.positions[a * 3], fm.positions[a * 3 + 1], fm.positions[a * 3 + 2]};
                        const Vec3 pb{fm.positions[b * 3], fm.positions[b * 3 + 1], fm.positions[b * 3 + 2]};
                        const Vec3 pc{fm.positions[c * 3], fm.positions[c * 3 + 1], fm.positions[c * 3 + 2]};
                        // The return (k = 0) faces into the opening, the band outwards.
                        const Vec3 want = k == 0 ? Vec3{xa, prof.hubY, sz * pa.z * sz} - pa : Vec3{0.0, 0.0, sz};
                        if (dot(cross(pb - pa, pc - pa), want) >= 0) { VisBuilder::tri(fm, a, b, d); VisBuilder::tri(fm, a, d, c); }
                        else { VisBuilder::tri(fm, a, d, b); VisBuilder::tri(fm, a, c, d); }
                    }
            }
        }
    }

    // Pressed door returns and the fixed aperture are separate closed edges.
    // The inner skin follows the actual physical cage depth; its perimeter closes here.
    for (int doorIndex = 0; doorIndex < 4; ++doorIndex) {
        const int sideIndex = doorIndex % 2;
        const auto& door = (doorIndex < 2 ? build.layout.frontDoors : build.layout.rearDoors)[static_cast<std::size_t>(sideIndex)];
        if (door.nodes.empty()) continue;
        const real side = sideIndex == 0 ? -1.0 : 1.0;
        const real thickness = std::abs(body.positions()[door.nodes[0]].z - body.positions()[door.nodes[1]].z);
        std::vector<Vec3> perimeter;
        auto point = [&](real x, int k) {
            const auto section = samples(x);
            return Vec3{x, section[static_cast<std::size_t>(k)].second, side * section[static_cast<std::size_t>(k)].first};
        };
        for (real x : xs) if (x >= door.rearX && x <= door.frontX) perimeter.push_back(point(x, 10));
        for (int k = 11; k <= 25; ++k) perimeter.push_back(point(door.frontX, k));
        for (auto it = xs.rbegin(); it != xs.rend(); ++it)
            if (*it >= door.rearX && *it < door.frontX) perimeter.push_back(point(*it, 25));
        for (int k = 24; k > 10; --k) perimeter.push_back(point(door.rearX, k));
        auto strip = [&](const std::string& material, const Vec3& a, const Vec3& b,
                         real nearDepth, real farDepth, const std::vector<std::uint32_t>& nodes) {
            MeshSurface& mesh = vb.surf(vb.partMaterial(material, nodes));
            const Vec3 inward{0, 0, -side};
            const Vec3 points[4] = {a + inward * nearDepth, b + inward * nearDepth,
                                    b + inward * farDepth, a + inward * farDepth};
            std::uint32_t index[4];
            for (int j = 0; j < 4; ++j) index[j] = vb.vertex(mesh, points[j], vb.skinNearest(points[j], nodes));
            if (sideIndex == 0) { VisBuilder::tri(mesh, index[0], index[2], index[1]); VisBuilder::tri(mesh, index[0], index[3], index[2]); }
            else { VisBuilder::tri(mesh, index[0], index[1], index[2]); VisBuilder::tri(mesh, index[0], index[2], index[3]); }
        };
        for (std::size_t i = 0; i < perimeter.size(); ++i) {
            const Vec3 a = perimeter[i], b = perimeter[(i + 1) % perimeter.size()];
            // Above the belt line the frame faces the occupants and is trimmed like the pillars.
            const std::string frame = (a.y + b.y) * 0.5 > bd.beltHeight + 0.02 ? "interior" : "paint";
            strip(frame, a, b, 0.0, thickness, door.nodes);
            strip(frame, a, b, thickness + 0.003, thickness + 0.055, bodyNodes);
            vb.tube("trim", a + Vec3{0, 0, -side * (thickness + 0.008)}, b + Vec3{0, 0, -side * (thickness + 0.008)}, 0.007, bodyNodes, 6);
        }
        // Window frame upright and a formed exterior pull handle travel with the door.
        for (real x : {door.rearX + 0.008, door.frontX - 0.008}) {
            const Vec3 lower = point(x, 21), upper = point(x, 25);
            vb.tube("trim", lower, upper, 0.012, door.nodes, 8);
        }
        const real handleX = door.rearX + 0.14;
        const real handleY = prof.yBelt(handleX) - 0.07;
        const real handleZ = side * (prof.halfW(handleX) - 0.016);
        vb.bevelBox("seam", {handleX, handleY, handleZ}, {0.072, 0.020, 0.009}, 0.009, door.nodes);
        vb.bevelBox("chrome", {handleX, handleY + 0.004, handleZ + side * 0.012}, {0.061, 0.009, 0.012}, 0.007, door.nodes);
        // Hinge plates remain on the pillar; the knuckles belong to the door.
        // No decorative beam spans the joint after its physical mounts detach.
        for (auto hingeNode : door.hingeNodes) {
            const Vec3 pivot = body.positions()[hingeNode];
            vb.bevelBox("chassis", pivot + Vec3{0.018, 0, -side * 0.023},
                        {0.027, 0.031, 0.009}, 0.006, bodyNodes);
            vb.tube("chrome", pivot + Vec3{0, -0.026, 0}, pivot + Vec3{0, 0.026, 0}, 0.012, door.nodes, 10);
            vb.bevelBox("chassis", pivot + Vec3{-0.021, 0, side * 0.008},
                        {0.024, 0.026, 0.008}, 0.005, door.nodes);
            for (real offset : {-0.019, 0.019})
                vb.tube("chrome", pivot + Vec3{0.028, offset, -side * 0.010},
                        pivot + Vec3{0.028, offset, -side * 0.016}, 0.005, bodyNodes, 6);
        }
        // Latch face, fasteners and lower drainage slots are visible when opened.
        const Vec3 latch = point(door.rearX, 17) + Vec3{0.002, 0, -side * thickness * 0.5};
        vb.box("chrome", latch, {0.004, 0.035, 0.018}, door.nodes);
        vb.box("seam", latch + Vec3{-0.004, 0, 0}, {0.003, 0.012, 0.010}, door.nodes);
        for (real offset : {-0.024, 0.024})
            vb.tube("trim", latch + Vec3{-0.007, offset, 0}, latch + Vec3{-0.010, offset, 0}, 0.004, door.nodes, 6);
        for (int drain = 0; drain < 3; ++drain) {
            const real x = door.rearX + (door.frontX - door.rearX) * (0.2 + drain * 0.3);
            const Vec3 bottom = point(x, 10);
            vb.box("seam", bottom + Vec3{0, -0.001, -side * thickness * 0.5}, {0.022, 0.002, 0.006}, door.nodes);
        }
    }

    // ---- end caps (front fascia / rear panel)
    Vec3 frontPlateSum{0, 0, 0};
    int frontPlateCount = 0;
    for (int end = 0; end < 2; ++end) {
        const std::size_t si = end == 0 ? 0 : xs.size() - 1;
        const real xEnd = xs[si];
        const real outward = end == 0 ? -1.0 : 1.0;
        const real bulge = end == 0 ? 0.035 : 0.05;
        const auto& s = smp[si];
        const int C = 16;
        auto capPoint = [&](int k, int c) {
            const real zk = s[static_cast<std::size_t>(k)].first;
            const real u = 2.0 * c / C - 1.0;
            const real z = zk * u;
            const real x = xEnd + outward * bulge * (1.0 - u * u) * (zk / hw) * (zk / hw);
            return Vec3{x, s[static_cast<std::size_t>(k)].second, z};
        };
        auto capMaterial = [&](const Vec3& p) -> std::string {
            const real az = std::abs(p.z);
            const real yB = prof.yBottom(xEnd);
            if (end == 1) {
                if (az < 0.24 && p.y > yB + 0.17 && p.y < yB + 0.28) return "plate";
                if (az < 0.62 * hw && p.y > yB + 0.03 && p.y < yB + 0.14) return "grille";
                if (p.y < yB + 0.13) return "trim";
                return "paint";
            }
            // The rear plate is a separate box above (with its lettering); a second white field
            // in the panel below it read as a doubled, blank plate.
            if (p.y < yB + 0.15) return "trim";
            return "paint";
        };
        for (int k = 0; k < K; ++k) {
            for (int c = 0; c < C; ++c) {
                const Vec3 p00 = capPoint(k, c), p01 = capPoint(k, c + 1), p10 = capPoint(k + 1, c), p11 = capPoint(k + 1, c + 1);
                if (std::abs(p00.y - p10.y) < 1e-5 && std::abs(p01.z - p00.z) < 1e-6) continue;
                const Vec3 midpoint = (p00 + p11) * 0.5;
                std::string mat = bumperMaterial(capMaterial(midpoint), midpoint.x, midpoint.y);
                if (end == 1 && capMaterial(midpoint) == "plate") {
                    frontPlateSum += midpoint;
                    ++frontPlateCount;
                }
                if (end == 0 && hasLid && midpoint.y > lidLatchY && mat.rfind("bumper_", 0) != 0) mat = "tailgate_" + mat;
                const auto& capNodes = surfaceNodes(mat);
                MeshSurface& m = vb.surf(mat);
                const std::uint32_t a = vb.vertex(m, p00, vb.skinNearest(p00, capNodes));
                const std::uint32_t b = vb.vertex(m, p01, vb.skinNearest(p01, capNodes));
                const std::uint32_t cc = vb.vertex(m, p11, vb.skinNearest(p11, capNodes));
                const std::uint32_t d = vb.vertex(m, p10, vb.skinNearest(p10, capNodes));
                const Vec3 n = cross(p01 - p00, p11 - p00);
                if (dot(n, Vec3{outward, 0, 0}) >= 0) { VisBuilder::tri(m, a, b, cc); VisBuilder::tri(m, a, cc, d); }
                else { VisBuilder::tri(m, a, cc, b); VisBuilder::tri(m, a, d, cc); }
            }
        }
    }

    // ---- light units and grille (separate geometry, skinned to the front / rear structure)
    {
        const real xf = L;
        const real hwF = prof.halfW(L - 0.04);
        const bool sport = bd.style == BodyStyle::Coupe;
        // Lamp strips that follow the plan outline of the nose and tail round into the corner:
        // flat across the face, then yawed segment by segment along the corner radius. A single
        // flat box either sat far inboard (the units were small squares beside the plate) or
        // was cut by the curving body and showed saw-toothed ends.
        auto lampStrip = [&](bool front, real sg, real zIn, real zOut, int segments,
                             const std::function<void(const Vec3& centre, const Vec3& n, const Vec3& t, real halfLen, int k)>& part) {
            const real rc = front ? prof.b.cornerRadiusFront : prof.b.cornerRadiusRear;
            const real wFace = (front ? prof.halfW(L - rc) : prof.halfW(rc));
            const real flat = wFace - rc;   // |z| up to here the face is straight
            auto faceAt = [&](real az, Vec3& n) {
                const real za = std::abs(az);
                real x, nx = 1.0, nz = 0.0;
                if (za <= flat) {
                    x = front ? L : 0.0;
                } else {
                    const real dz = std::min(za - flat, rc * 0.98);
                    const real dx = std::sqrt(std::max<real>(0.0, rc * rc - dz * dz));
                    x = front ? (L - rc + dx) : (rc - dx);
                    nx = dx / rc;
                    nz = dz / rc;
                }
                n = normalize(Vec3{front ? nx : -nx, 0.0, sg * nz});
                return x;
            };
            for (int k = 0; k < segments; ++k) {
                const real z0 = zIn + (zOut - zIn) * k / segments, z1 = zIn + (zOut - zIn) * (k + 1) / segments;
                Vec3 n0, n1, n;
                const Vec3 p0{faceAt(z0, n0), 0.0, z0}, p1{faceAt(z1, n1), 0.0, z1};
                faceAt(0.5 * (z0 + z1), n);
                const Vec3 centre = (p0 + p1) * 0.5;
                const Vec3 t = normalize(p1 - p0);
                part(centre, n, t, 0.5 * length(p1 - p0), k);
            }
        };
        // Headlight units: dark bezel, chrome reflector across the whole unit, a daytime-running
        // strip along the lower edge and two projector lenses on the face. 17 cm tall (12 on
        // coupes), from 40 % of the half width round most of the corner.
        const real housingH = sport ? 0.06 : 0.085;
        // The top stays just under the nose line: above it the face already curves back into the
        // bonnet and the paint would cover the unit's upper corners.
        // With the crisp bonnet line the face above the nose is a short raked panel up to the
        // bonnet edge: the units move up into it (top at 60 % of its height) and lean back with it,
        // so they sit right under the bonnet edge instead of below a strip of paint.
        real lift = 0.0, rake = 0.0;
        if (prof.crispHood) {
            const real yEdge = bd.noseHeight + 0.4 * (bd.hoodHeight - bd.noseHeight);
            lift = 0.6 * (yEdge - bd.noseHeight);
            rake = 0.5;   // run back 0.5 m per metre up (~27 degrees)
        }
        const real yH = bd.noseHeight - 0.012 - housingH + lift;
        const real rcF = prof.b.cornerRadiusFront;
        const real zLampIn = 0.40 * hwF, zLampOut = hwF - 0.18 * rcF;
        for (int side = 0; side < 2; ++side) {
            const real sg = side ? 1.0 : -1.0;
            lampStrip(true, sg, sg * zLampIn, sg * zLampOut, 6, [&](const Vec3& c, const Vec3& n, const Vec3& t, real hl, int k) {
                const Vec3 up = normalize(Vec3{0, 1, 0} - n * rake);
                const Vec3 base = c + Vec3{0, yH, 0} - n * (rake * std::max<real>(0.0, yH - bd.noseHeight + housingH * 0.3));
                const real len = hl * 1.12;   // overlap: no gaps at the joints
                vb.box("grille", base - n * 0.020, {0.026, housingH, len}, bodyNodes, n, up, t);
                vb.box("chrome", base + n * 0.004, {0.006, housingH - 0.012, len * 0.99}, bodyNodes, n, up, t);
                vb.box("headlight", base + n * 0.011 + up * (-housingH + 0.018), {0.004, 0.008, len * 0.99}, bodyNodes, n, up, t);
                if (k == 1 || k == 3) {
                    const Vec3 lc = base + up * 0.012;
                    vb.tube("grille", lc + n * 0.004, lc + n * 0.012, housingH * 0.52, bodyNodes, 20);
                    vb.tube("chrome", lc + n * 0.012, lc + n * 0.017, housingH * 0.44, bodyNodes, 20);
                    vb.tube("headlight", lc + n * 0.017, lc + n * 0.022, housingH * 0.30, bodyNodes, 20);
                }
            });
        }
        // Grille between the headlights.
        const real gw = std::max<real>(0.16, zLampIn - 0.05);
        vb.box("grille", {xf - 0.02, yH - 0.03, 0.0}, {0.03, 0.065, gw}, bodyNodes);
        for (int slat = 0; slat < 3; ++slat)
            vb.box("trim", {xf + 0.014, yH - 0.065 + slat * 0.032, 0.0}, {0.010, 0.005, gw * 0.94}, bodyNodes);
        vb.box("chrome", {xf + 0.002, yH + 0.048, 0.0}, {0.011, 0.008, gw}, bodyNodes);
        // Recessed lower intake, rolled surround and visible internal vanes.
        const real intakeY = prof.yBottom(L) + 0.115;
        const real intakeW = hwF * 0.55;
        vb.box("grille", {xf + 0.012, intakeY, 0}, {0.016, 0.046, intakeW}, frontNodes);
        for (real vertical : {-1.0, 1.0})
            vb.tube("trim", {xf + 0.032, intakeY + vertical * 0.047, -intakeW},
                    {xf + 0.032, intakeY + vertical * 0.047, intakeW}, 0.012, frontNodes, 8);
        for (int vane = -4; vane <= 4; ++vane)
            vb.box("chassis", {xf + 0.032, intakeY, vane * intakeW / 5}, {0.010, 0.039, 0.005}, frontNodes);
        for (real side : {-1.0, 1.0}) {
            const Vec3 lamp{xf - 0.004, intakeY + 0.02, side * hwF * 0.78};
            vb.tube("trim", lamp - Vec3{0.012, 0, 0}, lamp + Vec3{0.014, 0, 0}, 0.043, frontNodes, 20);
            vb.tube("chrome", lamp + Vec3{0.015, 0, 0}, lamp + Vec3{0.019, 0, 0}, 0.027, frontNodes, 20);
        }
        // Tail lights: housing, red lens with a brighter brake band, following the tail round the
        // corner like the headlights; a white reversing lamp on the inner segment.
        const real hwR = prof.halfW(0.04);
        const real yT = bd.tailHeight - 0.11;
        const real rcR = prof.b.cornerRadiusRear;
        const real th = sport ? 0.045 : 0.068;
        for (int side = 0; side < 2; ++side) {
            const real sg = side ? 1.0 : -1.0;
            const auto& tailNodes = yT > lidLatchY ? lidNodes : bodyNodes;
            lampStrip(false, sg, sg * (0.46 * hwR), sg * (hwR - 0.15 * rcR), 5, [&](const Vec3& c, const Vec3& n, const Vec3& t, real hl, int k) {
                const Vec3 up{0, 1, 0};
                const Vec3 base = c + Vec3{0, yT, 0};
                const real len = hl * 1.12;
                vb.box("grille", base - n * 0.016, {0.022, th, len}, tailNodes, n, up, t);
                if (k == 0) {
                    vb.box("taillight", base + n * 0.007 + up * (th * 0.35), {0.005, th * 0.55, len * 0.99}, tailNodes, n, up, t);
                    vb.box("reverselight", base + n * 0.007 + up * (-th * 0.55), {0.005, th * 0.30, len * 0.99}, tailNodes, n, up, t);
                } else {
                    vb.box("taillight", base + n * 0.007, {0.005, th - 0.010, len * 0.99}, tailNodes, n, up, t);
                }
                // One fine dark line splits the lens into a tail and a brake chamber. (Two lines plus
                // a divider at every segment joint made a coarse grid of red squares.)
                vb.box("grille", base + n * 0.0125 + up * (-0.12 * th), {0.0015, 0.002, len * 0.99}, tailNodes, n, up, t);
            });
        }
        vb.box("plate", {-0.020, yT - 0.145, 0.0}, {0.013, 0.046, 0.23}, yT - 0.145 > lidLatchY ? lidNodes : bodyNodes);
        // Lettering anchors: the rear plate's outer face, the front plate region's centre.
        vis.plateRear = vb.skinNearest({-0.034, yT - 0.145, 0.0}, yT - 0.145 > lidLatchY ? lidNodes : bodyNodes);
        if (frontPlateCount > 0) {
            const Vec3 c = frontPlateSum * (1.0 / frontPlateCount);
            vis.plateFront = vb.skinNearest({c.x + 0.004, c.y, 0.0}, frontNodes);
            vis.hasPlates = true;
        }
    }

    // Bull bar (CarBodyDef::bullbar): uprights and a top hoop of 60 mm tube, a lower cross bar,
    // two grille guards and the brackets back towards the bumper, skinned to its own nodes.
    if (build.layout.bullbarNodes.size() == 8) {
        const auto& P = body.positions();
        const auto& B = build.layout.bullbarNodes;
        const std::vector<std::uint32_t> bar(B.begin(), B.end());
        const Vec3 i00 = P[B[0]], i01 = P[B[1]], i10 = P[B[2]], i11 = P[B[3]];
        const Vec3 o00 = P[B[4]], o01 = P[B[5]], o10 = P[B[6]], o11 = P[B[7]];
        const real r = 0.03;
        // Rounded top corners: the uprights bend into the hoop over 9 cm.
        const Vec3 dz = normalize(o11 - o10) * 0.09, dy = normalize(o10 - o00) * 0.09;
        vb.tube("bullbar", o00, o10 - dy, r, bar, 12);
        vb.tube("bullbar", o01, o11 - dy, r, bar, 12);
        vb.tube("bullbar", o10 - dy, o10 + dz * 0.3 - dy * 0.3, r, bar, 12);
        vb.tube("bullbar", o11 - dy, o11 - dz * 0.3 - dy * 0.3, r, bar, 12);
        vb.tube("bullbar", o10 + dz * 0.3 - dy * 0.3, o10 + dz, r, bar, 12);
        vb.tube("bullbar", o11 - dz * 0.3 - dy * 0.3, o11 - dz, r, bar, 12);
        vb.tube("bullbar", o10 + dz, o11 - dz, r, bar, 12);
        const Vec3 lowL = o00 + (o10 - o00) * 0.22, lowR = o01 + (o11 - o01) * 0.22;
        vb.tube("bullbar", lowL, lowR, r * 0.9, bar, 12);
        for (real f : {0.36, 0.64}) {
            const Vec3 a = lowL + (lowR - lowL) * f, b = o10 + (o11 - o10) * f;
            vb.tube("bullbar", a, b, r * 0.75, bar, 10);
        }
        for (real t : {0.3, 0.7}) {
            vb.tube("bullbar", o00 + (o10 - o00) * t, i00 + (i10 - i00) * t, r * 0.8, bar, 10);
            vb.tube("bullbar", o01 + (o11 - o01) * t, i01 + (i11 - i01) * t, r * 0.8, bar, 10);
        }
    }

    // Bolt-on rear wing (CarBodyDef::rearWing): the blade between its four nodes, endplates, and
    // two struts down to the deck, skinned to the wing and mount nodes.
    if (build.layout.wingNodes.size() == 4 && build.layout.wingMounts.size() == 4) {
        const auto& P = body.positions();
        const auto& W = build.layout.wingNodes;
        const Vec3 fl = P[W[0]], fr = P[W[1]], rl = P[W[2]], rr = P[W[3]];
        const std::vector<std::uint32_t> wing(W.begin(), W.end());
        const Vec3 c = (fl + fr + rl + rr) * 0.25;
        const Vec3 ax = normalize((fl + fr) * 0.5 - (rl + rr) * 0.5);   // along the chord, forward
        const Vec3 az = normalize(fr - fl);
        const Vec3 ay = normalize(cross(az, ax));
        const real chord = length((fl + fr) * 0.5 - (rl + rr) * 0.5), span = length(fr - fl);
        vb.bevelBox("trim", c, {chord * 0.5, 0.013, span * 0.5}, 0.009, wing, ax, ay, az);
        for (real side : {-1.0, 1.0})
            vb.box("trim", c + az * (side * (span * 0.5 + 0.004)) - ay * 0.035, {chord * 0.56, 0.075, 0.004}, wing, ax, ay, az);
        std::vector<std::uint32_t> strutNodes = wing;
        for (auto n : build.layout.wingMounts) strutNodes.push_back(n);
        for (int side = 0; side < 2; ++side) {
            const Vec3 mount = (P[build.layout.wingMounts[static_cast<std::size_t>(side * 2)]] +
                                P[build.layout.wingMounts[static_cast<std::size_t>(side * 2 + 1)]]) * 0.5;
            const Vec3 top = c + az * ((side ? 1.0 : -1.0) * span * 0.32) - ay * 0.012;
            const Vec3 bottom{top.x - 0.03, mount.y - 0.02, top.z};
            const Vec3 up = normalize(top - bottom);
            vb.bevelBox("trim", (top + bottom) * 0.5, {0.045, length(top - bottom) * 0.5, 0.009}, 0.004, strutNodes,
                        normalize(cross(up, az)), up, az);
        }
    }

    // Black rocker mouldings between the wheel arches, a roof spoiler over the tailgate of
    // hatchbacks and SUVs, and roof rails on SUVs: the parts that break up a smooth painted body.
    {
        const real x0 = prof.xRA + prof.Ra + 0.05, x1 = prof.xFA - prof.Ra - 0.05;
        const int segs = 4;
        for (real side : {-1.0, 1.0}) {
            for (int k = 0; k < segs; ++k) {
                const real xa = x0 + (x1 - x0) * k / segs, xb = x0 + (x1 - x0) * (k + 1) / segs;
                const real xm = 0.5 * (xa + xb);
                const real hW = prof.halfW(xm);
                const real yB = prof.yBottom(xm);
                // The rocker face runs from (hW - 0.10, yB) up to (hW - 0.055, ySill = yB + 0.11).
                const Vec3 lo{xm, yB + 0.014, side * (hW - 0.093)};
                const Vec3 hi{xm, yB + 0.114, side * (hW - 0.052)};
                const Vec3 up = normalize(hi - lo);
                const Vec3 out = normalize(cross(Vec3{1, 0, 0}, up)) * side;
                vb.bevelBox("trim", (lo + hi) * 0.5 + out * 0.014, {(xb - xa) * 0.5 + 0.004, length(hi - lo) * 0.5, 0.014}, 0.009,
                            bodyNodes, Vec3{side, 0, 0}, up, out);
            }
        }
        if (bd.style == BodyStyle::Hatchback || bd.style == BodyStyle::SUV) {
            const auto sec = prof.section(prof.xRwTop + 0.04);
            const real top = sec.y[10];
            const real halfZ = sec.z[8] * 0.94;
            const real c = std::cos(0.16), s = std::sin(0.16);
            const Vec3 ax{-c, -s, 0}, ay{s, -c, 0};
            // 17 cm deep, overhanging the glass by ~9 cm like a factory hatch spoiler (it was 22 cm
            // and reached 14 cm past the glass: a black plank from behind).
            vb.bevelBox("trim", {prof.xRwTop - 0.01, top + 0.006, 0}, {0.085, 0.014, halfZ}, 0.012, lidNodes, ax, ay, {0, 0, 1});
            for (real side : {-1.0, 1.0})
                vb.bevelBox("trim", {prof.xRwTop - 0.005, top - 0.008, side * (halfZ - 0.012)}, {0.07, 0.019, 0.012}, 0.008,
                            lidNodes, ax, ay, {0, 0, 1});
        }
        if (bd.style == BodyStyle::Hatchback || bd.style == BodyStyle::SUV) {
            // Rear wiper parked along the bottom of the tailgate glass.
            const auto base = prof.section(prof.xRwBase + 0.02);
            const auto upper = prof.section(prof.xRwTop - 0.02);
            const Vec3 g0{prof.xRwBase + 0.02, base.y[8], 0.0};
            const Vec3 g1{prof.xRwTop - 0.02, upper.y[10], 0.0};
            const Vec3 dir = normalize(g1 - g0);
            const Vec3 normal = normalize(cross(dir, Vec3{0, 0, 1})) * -1.0;   // out of the glass, backwards
            const Vec3 pivot = g0 + dir * 0.05 + normal * 0.022;
            vb.tube("trim", pivot - normal * 0.012, pivot + normal * 0.010, 0.016, lidNodes, 12);
            const Vec3 tip = pivot + Vec3{0, 0, -0.34} + dir * 0.04;
            vb.tube("trim", pivot, tip, 0.006, lidNodes, 6);
            vb.box("trim", (pivot + tip) * 0.5 - normal * 0.006, {0.006, 0.004, 0.19}, lidNodes, dir, normal, {0, 0, 1});
        }
        {
            // Third brake light: under the roof spoiler of hatchbacks and SUVs, otherwise along the
            // top of the rear window. It shares the tail-light material, so it lights with the brakes.
            const auto sec = prof.section(prof.xRwTop + 0.04);
            const real top = sec.y[10];
            if (bd.style == BodyStyle::Hatchback || bd.style == BodyStyle::SUV) {
                const real c = std::cos(0.16), s = std::sin(0.16);
                const Vec3 ax{-c, -s, 0}, ay{s, -c, 0};
                vb.box("taillight", {prof.xRwTop - 0.085, top - 0.002, 0}, {0.006, 0.006, 0.13}, lidNodes, ax, ay, {0, 0, 1});
            } else {
                const auto glass = prof.section(prof.xRwTop - 0.05);
                vb.box("grille", {prof.xRwTop - 0.05, glass.y[10] - 0.028, 0}, {0.016, 0.012, 0.135}, bodyNodes);
                vb.box("taillight", {prof.xRwTop - 0.058, glass.y[10] - 0.028, 0}, {0.008, 0.006, 0.12}, bodyNodes);
            }
        }
        {
            // Fuel filler flap in the right-hand rear quarter panel, above the wheel arch.
            const real xf = prof.xRA + 0.02;
            const real yf = prof.yBelt(xf) - 0.13;
            // The panel bulges a little past the profile's half width at this height: sit proud of it.
            const real zf = prof.halfW(xf) + 0.004;
            // Only its shut line shows: a thin dark gap round a body-coloured flap.
            const real hx = 0.058, hy = 0.054, gap = 0.0018;
            vb.box("seam", {xf, yf + hy, zf}, {hx + gap, gap, 0.002}, bodyNodes);
            vb.box("seam", {xf, yf - hy, zf}, {hx + gap, gap, 0.002}, bodyNodes);
            vb.box("seam", {xf + hx, yf, zf}, {gap, hy, 0.002}, bodyNodes);
            vb.box("seam", {xf - hx, yf, zf}, {gap, hy, 0.002}, bodyNodes);
        }
        {
            // Shark-fin antenna at the back of the roof.
            const real xa = prof.xRwTop + 0.14;
            const real top = prof.section(xa).y[10];
            vb.bevelBox("trim", {xa, top + 0.026, 0}, {0.075, 0.026, 0.013}, 0.012, bodyNodes);
            vb.bevelBox("trim", {xa - 0.035, top + 0.050, 0}, {0.032, 0.018, 0.010}, 0.009, bodyNodes);
        }
        {
            // Red reflectors in the lower rear bumper.
            const real y = bd.tailHeight - 0.36;
            const real hz = prof.halfW(0.04) - 0.13;
            for (real side : {-1.0, 1.0})
                vb.bevelBox("reflector", {-0.004, y, side * hz}, {0.010, 0.014, 0.055}, 0.006, rearNodes);
        }
        if (bd.style == BodyStyle::SUV) {
            const real xa = prof.xRwTop + 0.12, xb = prof.xWsTop - 0.10;
            for (real side : {-1.0, 1.0}) {
                const auto sa = prof.section(xa), sb = prof.section(xb);
                const Vec3 a{xa, sa.y[10] + 0.045, side * sa.z[8] * 0.78};
                const Vec3 b{xb, sb.y[10] + 0.045, side * sb.z[8] * 0.78};
                vb.tube("trim", a, b, 0.014, bodyNodes, 10);
                for (real t : {0.0, 0.5, 1.0}) {
                    const Vec3 foot = a + (b - a) * t;
                    vb.bevelBox("trim", foot - Vec3{0, 0.022, 0}, {0.035, 0.024, 0.016}, 0.008, bodyNodes);
                }
            }
        }
    }

    // Bumper reinforcement and recessed brackets stay on the chassis when the
    // painted fascia departs. Return lips give the exposed plastic shell depth.
    if (bd.detachableBumpers) {
        for (int end = 0; end < 2; ++end) {
            const bool front = end == 0;
            const auto& panelNodes = front ? frontNodes : rearNodes;
            const real sign = front ? 1.0 : -1.0;
            const real x = front ? L - 0.25 : 0.25;
            const real top = front ? bd.noseHeight - 0.16 : bd.tailHeight - 0.28;
            const real bottom = prof.yBottom(x) + 0.035;
            const real mid = (top + bottom) * 0.5;
            const real half = prof.halfW(x) * 0.86;
            vb.box("chassis", {x - sign * 0.055, mid, 0}, {0.035, 0.065, half}, bodyNodes);
            for (real side : {-1.0, 1.0}) {
                vb.box("engine", {x - sign * 0.17, mid, side * 0.40}, {0.10, 0.045, 0.055}, bodyNodes);
                for (int rib = 0; rib < 4; ++rib)
                    vb.box("chassis", {x - sign * (0.11 + rib * 0.035), mid, side * 0.40}, {0.004, 0.049, 0.058}, bodyNodes);
                vb.tube("chrome", {x - sign * 0.015, mid + 0.035, side * 0.40},
                        {x + sign * 0.008, mid + 0.035, side * 0.40}, 0.010, bodyNodes, 6);
            }
            // Inner return/flange travels with the skin, never with the crash bar.
            vb.box("trim", {x + sign * 0.10, bottom + 0.012, 0}, {0.085, 0.012, half}, panelNodes);
            for (real side : {-1.0, 1.0})
                vb.box("trim", {x + sign * 0.07, mid, side * half}, {0.07, (top - bottom) * 0.43, 0.012}, panelNodes);
        }
    }

    // ---- mirrors
    for (int side = 0; side < 2; ++side) {
        const real sgn = side ? 1.0 : -1.0;
        const auto& doorNodes = build.layout.frontDoors[static_cast<std::size_t>(side)].nodes;
        const auto& mirrorNodes = doorNodes.empty() ? bodyNodes : doorNodes;
        const real x = prof.xCowl - 0.16;
        const real y = prof.yBelt(x) + 0.075;
        const real z = sgn * (prof.shoulderHalf(x) + 0.11);
        const Vec3 opticalCenter{x - 0.043, y, z};
        const real eyeX = prof.xB + 0.12;
        const Vec3 eye{eyeX, std::min(bd.beltHeight + 0.29, prof.yRoofRail(eyeX) - 0.10), -0.36};
        // A real adjusted mirror: its normal bisects the eye ray and a rearward
        // horizon ray. A vertical rear-facing plate reflected only nearby ground.
        const Vec3 rearward = normalize(Vec3{-1, 0, sgn * 0.12});
        const Vec3 opticalNormal = normalize(normalize(eye - opticalCenter) + rearward);
        const Vec3 ax = -opticalNormal;
        const Vec3 up = normalize(Vec3{0, 1, 0} - ax * ax.y);
        const Vec3 right = cross(ax, up);
        const Vec3 trimCenter = opticalCenter + ax * 0.043 - up * 0.009;
        const Vec3 paintCenter = opticalCenter + ax * 0.049 + up * 0.008;
        vb.oval("trim", trimCenter, {0.075, 0.052, 0.103}, mirrorNodes, trimCenter.x - 0.040, ax, up, right);
        vb.oval("paint", paintCenter, {0.073, 0.047, 0.101}, mirrorNodes, paintCenter.x - 0.046, ax, up, right);
        vb.mirrorInsert(opticalCenter, 0.029, 0.068, mirrorNodes, side == 0 ? "mirror_left" : "mirror_right", up, right);
        vb.tube("trim", {x + 0.01, y - 0.03, sgn * (prof.shoulderHalf(x) + 0.02)},
                opticalCenter + ax * 0.057 - up * 0.030, 0.016, mirrorNodes, 10);
    }

    // Window seals are split at the opening boundary so none bridge an open door.
    for (int sideIndex = 0; sideIndex < 2; ++sideIndex) {
        const real side = sideIndex == 0 ? -1.0 : 1.0;
        const auto& door = build.layout.frontDoors[static_cast<std::size_t>(sideIndex)];
        std::vector<real> sealX;
        for (int i = 0; i <= 40; ++i) sealX.push_back(prof.xRwBase + (prof.xCowl - prof.xRwBase) * i / 40);
        const auto& rearDoor = build.layout.rearDoors[static_cast<std::size_t>(sideIndex)];
        if (!door.nodes.empty()) { sealX.push_back(door.rearX); sealX.push_back(door.frontX); }
        if (!rearDoor.nodes.empty()) { sealX.push_back(rearDoor.rearX); sealX.push_back(rearDoor.frontX); }
        std::sort(sealX.begin(), sealX.end());
        for (std::size_t i = 0; i + 1 < sealX.size(); ++i) {
            const real x0 = sealX[i], x1 = sealX[i + 1], mid = (x0 + x1) * 0.5;
            const auto& nodes = !door.nodes.empty() && mid > door.rearX && mid < door.frontX ? door.nodes
                              : (!rearDoor.nodes.empty() && mid > rearDoor.rearX && mid < rearDoor.frontX ? rearDoor.nodes : bodyNodes);
            const auto a = samples(x0), b = samples(x1);
            for (int k : {21, 25})
                vb.tube("trim", {x0, a[k].second - 0.005, side * (a[k].first + 0.004)},
                        {x1, b[k].second - 0.005, side * (b[k].first + 0.004)}, 0.009, nodes, 8);
        }
        // The structural A pillar remains part of the passenger cell.
        for (int i = 0; i < 12; ++i) {
            const real x0 = prof.xWsTop + (prof.xCowl - prof.xWsTop) * i / 12;
            const real x1 = prof.xWsTop + (prof.xCowl - prof.xWsTop) * (i + 1) / 12;
            const Section a = prof.section(x0), b = prof.section(x1);
            vb.tube("paint", {x0, a.y[8] + 0.004, side * a.z[8]},
                    {x1, b.y[8] + 0.004, side * b.z[8]}, 0.022, bodyNodes, 10,
                    "interior", normalize(Vec3{-0.2, -0.45, -side}));
        }
    }

    // ---- interior (seats, dashboard, steering wheel)
    {
        const real yFloor = prof.yBottom(prof.xB) + 0.10;
        const real beltY = bd.beltHeight;
        const real dashX = prof.xCowl - 0.22;
        const real dashHalf = prof.shoulderHalf(dashX) - 0.10;
        const real seatX = prof.xB + 0.10 + bd.seatShift;
        const real benchX = prof.xB - 0.55 + bd.rearSeatShift;
        const bool rearSeats = bd.doors >= 4 || bd.style != BodyStyle::Coupe;
        // Carpet: rear footwell to the toe board, over a transmission tunnel along the centre.
        {
            const real xRear = rearSeats ? benchX - 0.26 : prof.xB - 0.45;
            const real xHeel = seatX + 0.52, xFire = dashX + 0.06;
            std::vector<std::vector<Vec3>> rows;
            constexpr int n = 18;
            for (int i = 0; i <= n; ++i) {
                const real x = xRear + (xFire - xRear) * i / n;
                const real rise = x > xHeel ? 0.24 * (x - xHeel) / std::max<real>(0.05, xFire - xHeel) : 0.0;
                const real w = std::max<real>(0.30, prof.shoulderHalf(x) - 0.10);
                std::vector<Vec3> row;
                for (real z : {-w, -0.5 * w, -0.20, -0.13, -0.075, 0.075, 0.13, 0.20, 0.5 * w, w}) {
                    const real a = std::abs(z);
                    const real tunnel = a < 0.075 ? 0.13 : a < 0.20 ? 0.13 * (0.20 - a) / 0.125 : 0.0;
                    row.push_back({x, yFloor - 0.005 + std::max(rise, tunnel), z});
                }
                rows.push_back(row);
            }
            vb.sheet("carpet", rows, {0, 1, 0}, bodyNodes);
        }
        // Headliner following the roof, with sun visors and the rear-view mirror.
        {
            std::vector<std::vector<Vec3>> rows;
            constexpr int n = 14;
            const real x0 = prof.xRwTop + 0.02, x1 = prof.xWsTop - 0.02;
            auto roofAt = [&](real x, real zz) {
                const Section sec = prof.section(x);
                const real edge = sec.z[8] - 0.05;
                const real yc = sec.y[10] - 0.045, ye = sec.y[8] - 0.035;
                return Vec3{x, lerp(yc, ye, zz * zz), zz * edge};
            };
            for (int i = 0; i <= n; ++i) {
                const real x = x0 + (x1 - x0) * i / n;
                std::vector<Vec3> row;
                for (int j = 0; j <= 12; ++j) row.push_back(roofAt(x, -1.0 + 2.0 * j / 12));
                rows.push_back(row);
            }
            vb.sheet("headliner", rows, {0, -1, 0}, bodyNodes);
            const real visorX = x1 - 0.12;
            for (real z : {-0.34, 0.34}) {
                const Vec3 hinge = roofAt(visorX, z / std::max<real>(0.2, prof.section(visorX).z[8] - 0.05));
                vb.bevelBox("headliner", hinge + Vec3{0.0, -0.022, 0.0}, {0.085, 0.011, 0.165}, 0.009, bodyNodes,
                            normalize(Vec3{1, 0.18, 0}), normalize(Vec3{-0.18, 1, 0}), {0, 0, 1});
            }
            const Vec3 mount = roofAt(x1 - 0.06, 0.0);
            vb.tube("trim", mount + Vec3{0, 0.01, 0}, mount + Vec3{-0.03, -0.075, 0}, 0.009, bodyNodes, 8);
            vb.bevelBox("trim", mount + Vec3{-0.035, -0.105, 0}, {0.022, 0.036, 0.115}, 0.014, bodyNodes);
            vb.box("chrome", mount + Vec3{-0.058, -0.105, 0}, {0.002, 0.028, 0.104}, bodyNodes);
        }
        vb.bevelBox("interior", {dashX, beltY - 0.10, 0.0}, {0.16, 0.09, dashHalf}, 0.035, bodyNodes);
        vb.bevelBox("trim", {dashX + 0.03, beltY - 0.008, 0.0}, {0.17, 0.027, dashHalf}, 0.022, bodyNodes);
        vb.box("chrome", {dashX - 0.162, beltY - 0.051, 0.0}, {0.010, 0.008, dashHalf - 0.014}, bodyNodes);
        vb.box("upholstery", {dashX - 0.164, beltY - 0.094, 0.0}, {0.008, 0.024, dashHalf - 0.015}, bodyNodes);
        // Centre display bezel; its live face is attached to the dashboard anchor in Godot.
        vb.bevelBox("trim", {dashX - 0.169, beltY + 0.025, 0.025}, {0.022, 0.075, 0.128}, 0.015, bodyNodes);
        for (real ventZ : {-dashHalf + 0.085, dashHalf - 0.085}) {
            vb.bevelBox("chrome", {dashX - 0.168, beltY - 0.01, ventZ}, {0.012, 0.044, 0.065}, 0.009, bodyNodes);
            vb.bevelBox("seam", {dashX - 0.182, beltY - 0.01, ventZ}, {0.006, 0.036, 0.057}, 0.005, bodyNodes);
            for (int slot = 0; slot < 4; ++slot)
                vb.box("trim", {dashX - 0.190, beltY - 0.035 + slot * 0.016, ventZ}, {0.004, 0.002, 0.054}, bodyNodes);
        }
        vb.box("seam", {dashX - 0.163, beltY - 0.117, 0.37}, {0.009, 0.049, 0.15}, bodyNodes);
        vb.box("trim", {dashX - 0.173, beltY - 0.093, 0.37}, {0.006, 0.009, 0.044}, bodyNodes);
        const real clusterY = beltY + 0.080;
        vb.bevelBox("trim", {dashX - 0.055, clusterY + 0.006, -0.36}, {0.10, 0.052, 0.179}, 0.035, bodyNodes);
        vb.box("seam", {dashX - 0.158, clusterY, -0.36}, {0.008, 0.046, 0.163}, bodyNodes);
        vis.dashboard = vb.skinNearest({dashX - 0.170, clusterY, -0.36}, bodyNodes);
        MeshSurface& bezels = vb.surf("chrome");
        for (real lateral : {-0.444, -0.276}) {
            const Vec3 face{dashX - 0.168, clusterY, lateral};
            for (int segment = 0; segment < 16; ++segment) {
                const real a = 2.0 * kPi * segment / 16;
                const real b = 2.0 * kPi * (segment + 1) / 16;
                const Vec3 u{0.0, std::cos(a), std::sin(a)}, v{0.0, std::cos(b), std::sin(b)};
                const auto add = [&](const Vec3& p) { return vb.vertex(bezels, p, vb.skinNearest(p, bodyNodes)); };
                const auto aOuter = add(face + u * 0.042), aInner = add(face + u * 0.039);
                const auto bOuter = add(face + v * 0.042), bInner = add(face + v * 0.039);
                VisBuilder::tri(bezels, aOuter, aInner, bOuter);
                VisBuilder::tri(bezels, aInner, bInner, bOuter);
            }
        }
        const real pillarFootX = prof.xCowl - 0.075;
        const Section pillarFoot = prof.section(pillarFootX), pillarTop = prof.section(prof.xWsTop);
        for (real side : {-1.0, 1.0}) {
            const Vec3 foot{pillarFootX, pillarFoot.y[8] - 0.02, side * (pillarFoot.z[8] - 0.025)};
            const Vec3 top{prof.xWsTop, pillarTop.y[8] - 0.018, side * (pillarTop.z[8] - 0.024)};
            const Vec3 axis = normalize(top - foot);
            const Vec3 width = normalize(cross(axis, Vec3{0, 1, 0}));
            vb.box("headliner", (foot + top) * 0.5, {length(top - foot) * 0.5, 0.018, 0.016}, bodyNodes,
                   axis, cross(width, axis), width);
        }
        vb.bevelBox("interior", {dashX - 0.17, beltY - 0.15, 0.02}, {0.032, 0.11, 0.135}, 0.025, bodyNodes);
        vb.box("seam", {dashX - 0.207, beltY - 0.126, 0.02}, {0.009, 0.041, 0.102}, bodyNodes);
        for (int slat = 0; slat < 3; ++slat) {
            vb.box("trim", {dashX - 0.218, beltY - 0.147 + slat * 0.018, 0.02}, {0.007, 0.004, 0.091}, bodyNodes);
        }
        vb.bevelBox("trim", {dashX - 0.25, yFloor + 0.20, 0.0}, {0.30, 0.10, 0.09}, 0.035, bodyNodes);  // console
        // Rear part of the console between the seats: cup holders, storage box and a padded armrest.
        vb.bevelBox("trim", {seatX + 0.02, yFloor + 0.17, 0.0}, {0.20, 0.12, 0.085}, 0.03, bodyNodes);
        vb.pillow("interior", {seatX - 0.16, 0, 0}, {seatX + 0.14, 0, 0}, {0, 0, 1}, {0, 1, 0}, [&](real) {
            return std::vector<std::pair<real, real>>{{-0.08, yFloor + 0.27}, {0.08, yFloor + 0.27}, {0.085, yFloor + 0.32},
                                                      {0.05, yFloor + 0.345}, {-0.05, yFloor + 0.345}, {-0.085, yFloor + 0.32}};
        }, 0.03, bodyNodes, 4);
        for (real z : {-0.04, 0.04}) vb.tube("seam", {seatX + 0.25, yFloor + 0.27, z}, {seatX + 0.25, yFloor + 0.30, z}, 0.032, bodyNodes, 14);
        vb.box("chrome", {dashX - 0.24, yFloor + 0.303, 0.0}, {0.11, 0.005, 0.073}, bodyNodes);
        vb.box("seam", {dashX - 0.24, yFloor + 0.313, 0.0}, {0.072, 0.014, 0.048}, bodyNodes);
        vb.bevelBox("trim", {dashX - 0.24, yFloor + 0.353, 0.0}, {0.025, 0.045, 0.020}, 0.016, bodyNodes);
        vb.box("chrome", {dashX - 0.24, yFloor + 0.401, 0.0}, {0.034, 0.012, 0.026}, bodyNodes);
        const real ySeat = yFloor - bd.seatDrop;
        // Front seats: frame and rails, a contoured cushion and backrest with side bolsters and a
        // two-tone centre, an adjustable headrest on chrome posts, and the belt buckle.
        const Vec3 backUp = normalize(Vec3{-0.24, 1, 0});
        const Vec3 backFwd = normalize(Vec3{1, 0.24, 0});
        for (real zs : {-0.36, 0.36}) {
            const real inboard = zs < 0 ? 1.0 : -1.0;
            vb.box("seat_frame", {seatX + 0.05, ySeat + 0.065, zs}, {0.20, 0.05, 0.18}, bodyNodes);
            for (real r : {-0.17, 0.17})
                vb.box("seat_frame", {seatX + 0.05, ySeat + 0.012, zs + r}, {0.27, 0.012, 0.016}, bodyNodes);
            const real bot = ySeat + 0.11;
            vb.pillow("fabric", {seatX - 0.20, 0, zs}, {seatX + 0.30, 0, zs}, {0, 0, 1}, {0, 1, 0}, [&](real t) {
                const real yc = ySeat + 0.235 + 0.02 * t;
                const real yb = yc + 0.05 * (1.0 - 0.55 * t);
                return std::vector<std::pair<real, real>>{
                    {-0.24, bot}, {0.24, bot}, {0.255, bot + 0.06}, {0.25, yc + 0.02}, {0.225, yb}, {0.19, yb - 0.006},
                    {0.15, yc + 0.012}, {0.10, yc}, {0.0, yc - 0.004}, {-0.10, yc}, {-0.15, yc + 0.012},
                    {-0.19, yb - 0.006}, {-0.225, yb}, {-0.25, yc + 0.02}, {-0.255, bot + 0.06}};
            }, 0.055, bodyNodes);
            vb.pillow("seat_insert", {seatX - 0.15, 0, zs}, {seatX + 0.25, 0, zs}, {0, 0, 1}, {0, 1, 0}, [&](real t) {
                const real yc = ySeat + 0.235 + 0.02 * t;
                return std::vector<std::pair<real, real>>{{-0.13, yc - 0.012}, {0.13, yc - 0.012}, {0.135, yc + 0.004},
                                                          {0.0, yc + 0.007}, {-0.135, yc + 0.004}};
            }, 0.03, bodyNodes, 4);
            const Vec3 backA{seatX - 0.17, ySeat + 0.22, zs};
            const real backH = 0.62;
            auto backProfile = [](real t, real scale) {
                const real w = 0.245 - 0.03 * t;
                const real vc = 0.03 + 0.016 * std::exp(-std::pow((t - 0.25) / 0.15, 2.0));
                const real vbol = vc + 0.065 * (t < 0.72 ? 1.0 : std::max<real>(0.2, 1.0 - (t - 0.72) / 0.3));
                std::vector<std::pair<real, real>> pts{
                    {-w, -0.065}, {w, -0.065}, {w + 0.005, vbol - 0.025}, {w - 0.03, vbol}, {w - 0.07, vbol - 0.01},
                    {w - 0.10, vc + 0.006}, {0.0, vc}, {-(w - 0.10), vc + 0.006}, {-(w - 0.07), vbol - 0.01},
                    {-(w - 0.03), vbol}, {-(w + 0.005), vbol - 0.025}};
                for (auto& p : pts) p.first *= scale;
                return pts;
            };
            vb.pillow("fabric", backA, backA + backUp * backH, {0, 0, 1}, backFwd,
                      [&](real t) { return backProfile(t, 1.0); }, 0.06, bodyNodes);
            vb.pillow("seat_insert", backA + backUp * 0.06, backA + backUp * (backH - 0.16), {0, 0, 1}, backFwd, [&](real t) {
                const real vc = 0.03 + 0.016 * std::exp(-std::pow((t * 0.7 + 0.07 - 0.25) / 0.15, 2.0));
                return std::vector<std::pair<real, real>>{{-0.12, vc - 0.015}, {0.12, vc - 0.015}, {0.125, vc + 0.004},
                                                          {0.0, vc + 0.008}, {-0.125, vc + 0.004}};
            }, 0.03, bodyNodes, 4);
            const Vec3 headC = backA + backUp * (backH + 0.13) + backFwd * 0.005;
            vb.pillow("fabric", headC + Vec3{0, 0, -0.135}, headC + Vec3{0, 0, 0.135}, backFwd, backUp, [](real) {
                std::vector<std::pair<real, real>> pts;
                for (int i = 0; i < 16; ++i) {
                    const real a = 2.0 * kPi * i / 16;
                    const real c = std::cos(a), sn = std::sin(a);
                    pts.push_back({0.048 * std::copysign(std::pow(std::abs(c), 0.6), c), 0.088 * std::copysign(std::pow(std::abs(sn), 0.6), sn)});
                }
                return pts;
            }, 0.04, bodyNodes, 3);
            for (real r : {-0.065, 0.065})
                vb.tube("seat_frame", backA + backUp * (backH - 0.03) + Vec3{0, 0, r}, headC - backUp * 0.07 + Vec3{0, 0, r}, 0.0065, bodyNodes, 8);
            // Three-point belt lying across the seat: shoulder strap from the outboard top of the
            // backrest to the inboard buckle, lap strap across the cushion.
            {
                const real outboard = -inboard;
                const Vec3 shoulder = backA + backUp * (backH - 0.06) + Vec3{0, 0, outboard * 0.17} + backFwd * 0.075;
                const Vec3 chest = backA + backUp * (backH * 0.45) + Vec3{0, 0, inboard * 0.02} + backFwd * 0.075;
                const Vec3 buckle{seatX - 0.13, ySeat + 0.31, zs + inboard * 0.25};
                const Vec3 hipOut{seatX - 0.10, ySeat + 0.31, zs + outboard * 0.25};
                auto strap = [&](const Vec3& a, const Vec3& b, const Vec3& facing) {
                    const Vec3 along = normalize(b - a);
                    const Vec3 width = normalize(cross(facing, along));
                    vb.box("seat_belt", (a + b) * 0.5, {length(b - a) * 0.5, 0.0025, 0.024}, bodyNodes, along, normalize(cross(along, width)), width);
                };
                strap(shoulder, chest, backFwd);
                strap(chest, buckle + Vec3{0.02, 0.0, 0.0}, normalize(backFwd + Vec3{0, 0.6, 0}));
                strap(hipOut, buckle, Vec3{0, 1, 0});
            }
            // Buckle on the inboard side, belt strap and retractor cover on the B pillar.
            vb.bevelBox("seat_frame", {seatX - 0.13, ySeat + 0.27, zs + inboard * 0.27}, {0.022, 0.045, 0.014}, 0.008, bodyNodes,
                        backFwd, backUp, {0, 0, 1});
            vb.box("seat_frame", {seatX - 0.125, ySeat + 0.325, zs + inboard * 0.27}, {0.012, 0.012, 0.004}, bodyNodes);
        }
        {
            const Section sb0 = prof.section(prof.xB);
            for (real side : {-1.0, 1.0}) {
                const Vec3 lower{prof.xB - 0.005, bd.beltHeight - 0.06, side * (sb0.z[7] - 0.035)};
                const Vec3 upper{prof.xB - 0.005, sb0.y[8] - 0.04, side * (sb0.z[8] - 0.035)};
                const Vec3 along = normalize(upper - lower);
                const Vec3 inward{0, 0, -side};
                const Vec3 across = normalize(cross(along, inward));
                vb.bevelBox("headliner", (lower + upper) * 0.5, {length(upper - lower) * 0.5 + 0.02, 0.045, 0.018}, 0.012, bodyNodes,
                            along, across, inward);
                vb.box("belt", (lower + upper) * 0.5 + inward * 0.021 + along * 0.03, {length(upper - lower) * 0.5 - 0.02, 0.022, 0.003},
                       bodyNodes, along, across, inward);
                vb.bevelBox("trim", upper - along * 0.05 + inward * 0.026, {0.022, 0.024, 0.012}, 0.008, bodyNodes, along, across, inward);
                vb.bevelBox("headliner", lower - along * 0.10 + inward * 0.005, {0.09, 0.055, 0.03}, 0.02, bodyNodes, along, across, inward);
            }
        }
        // Pedal box: brake and throttle, clutch for a manual gearbox.
        {
            // Heel point ahead of the seat, pads 20 cm further on but always short of the bulkhead,
            // and their height from where they sit along the sloping footwell. With the seat close
            // to the dashboard (the Aurora) the slope ratio blew up and the pads stood ~1 m above
            // the floor, sticking up through the dashboard in front of the driver.
            const real xFire = dashX + 0.06;
            const real xHeel = std::min(seatX + 0.52, xFire - 0.30);
            const real padX = std::min(xHeel + 0.20, xFire - 0.10);
            const real slope = std::clamp((padX - xHeel) / std::max<real>(0.05, xFire - xHeel), 0.0, 1.0);
            const real padY = yFloor + 0.10 + 0.24 * slope;
            const Vec3 pivotY{0, beltY - 0.22, 0};
            struct Pedal { real z, hw, hh; };
            std::vector<Pedal> pedals{{-0.31, 0.040, 0.030}, {-0.20, 0.022, 0.055}};
            if (!build.def.engine.automatic) pedals.push_back({-0.43, 0.034, 0.030});
            for (const Pedal& pd : pedals) {
                const Vec3 pad{padX - 0.02, padY + 0.05, pd.z};
                vb.bevelBox("tire", pad, {0.010, pd.hh, pd.hw}, 0.006, bodyNodes, normalize(Vec3{1, 0.55, 0}), normalize(Vec3{-0.55, 1, 0}), {0, 0, 1});
                vb.tube("chassis", pad + Vec3{0.012, pd.hh * 0.6, 0}, Vec3{dashX - 0.02, pivotY.y, pd.z}, 0.007, bodyNodes, 6);
            }
        }
        for (real zs : {-0.36, 0.36}) {
            const real doorSide = zs < 0 ? -1.0 : 1.0;
            const auto& panelNodes = build.layout.frontDoors[zs < 0 ? 0 : 1].nodes;
            const auto& cardNodes = panelNodes.empty() ? bodyNodes : panelNodes;
            const real doorX = (dashX + seatX) * 0.5;
            const real doorZ = doorSide * (prof.shoulderHalf(doorX) - 0.090);
            vb.bevelBox("interior", {doorX, beltY - 0.16, doorZ}, {0.31, 0.12, 0.040}, 0.022, cardNodes);
            vb.bevelBox("trim", {doorX, beltY - 0.12, doorZ - doorSide * 0.045}, {0.23, 0.028, 0.034}, 0.020, cardNodes);
            vb.box("chrome", {doorX + 0.11, beltY - 0.053, doorZ - doorSide * 0.047}, {0.060, 0.011, 0.012}, cardNodes);
            vb.box("upholstery", {doorX, beltY - 0.24, doorZ - doorSide * 0.044}, {0.25, 0.055, 0.008}, cardNodes);
            // Window switches and a visible speaker grille.
            for (int key = 0; key < 3; ++key)
                vb.box("seam", {doorX + 0.08 - key * 0.035, beltY - 0.088, doorZ - doorSide * 0.055}, {0.012, 0.004, 0.012}, cardNodes);
            for (int slat = 0; slat < 5; ++slat)
                vb.box("seam", {doorX + 0.15, beltY - 0.28 + slat * 0.014, doorZ - doorSide * 0.055}, {0.065, 0.003, 0.003}, cardNodes);
        }
        // Rear door cards with a pull handle, armrest and speaker grille travel with the rear doors.
        for (int sideIndex = 0; sideIndex < 2; ++sideIndex) {
            const auto& rearDoor = build.layout.rearDoors[static_cast<std::size_t>(sideIndex)];
            if (rearDoor.nodes.empty()) continue;
            const real doorSide = sideIndex == 0 ? -1.0 : 1.0;
            const real doorX = (rearDoor.rearX + rearDoor.frontX) * 0.5;
            const real doorZ = doorSide * (prof.shoulderHalf(doorX) - 0.090);
            const real halfLen = std::max<real>(0.12, (rearDoor.frontX - rearDoor.rearX) * 0.5 - 0.07);
            vb.bevelBox("interior", {doorX, beltY - 0.16, doorZ}, {halfLen, 0.12, 0.040}, 0.022, rearDoor.nodes);
            vb.bevelBox("trim", {doorX, beltY - 0.12, doorZ - doorSide * 0.045}, {halfLen * 0.7, 0.028, 0.034}, 0.020, rearDoor.nodes);
            vb.box("chrome", {doorX + halfLen * 0.4, beltY - 0.053, doorZ - doorSide * 0.047}, {0.050, 0.011, 0.012}, rearDoor.nodes);
            vb.box("upholstery", {doorX, beltY - 0.24, doorZ - doorSide * 0.044}, {halfLen * 0.8, 0.055, 0.008}, rearDoor.nodes);
            for (int slat = 0; slat < 4; ++slat)
                vb.box("seam", {doorX - halfLen * 0.5, beltY - 0.28 + slat * 0.014, doorZ - doorSide * 0.055}, {0.05, 0.003, 0.003}, rearDoor.nodes);
        }
        if (rearSeats) {
            const real yBench = yFloor - 0.5 * bd.seatDrop;
            // Rear bench: two contoured places with a raised centre, backrest and outer headrests.
            const real W = prof.shoulderHalf(benchX) - 0.14;
            const real place = std::min<real>(0.37, W - 0.18);
            auto dip = [&](real u) {
                const real d = std::min(std::abs(u - place), std::abs(u + place));
                return std::exp(-std::pow(d / 0.16, 2.0));
            };
            vb.pillow("fabric", {benchX - 0.22, 0, 0}, {benchX + 0.25, 0, 0}, {0, 0, 1}, {0, 1, 0}, [&](real t) {
                std::vector<std::pair<real, real>> pts{{-W, yBench + 0.10}, {W, yBench + 0.10}};
                for (int i = 0; i <= 16; ++i) {
                    const real u = W - 2.0 * W * i / 16;
                    pts.push_back({u, yBench + 0.245 + 0.018 * t - 0.022 * dip(u)});
                }
                return pts;
            }, 0.05, bodyNodes);
            const Vec3 rUp = normalize(Vec3{-0.30, 1, 0}), rFwd = normalize(Vec3{1, 0.30, 0});
            const Vec3 rA{benchX - 0.21, yBench + 0.23, 0};
            vb.pillow("fabric", rA, rA + rUp * 0.56, {0, 0, 1}, rFwd, [&](real t) {
                std::vector<std::pair<real, real>> pts{{-W, -0.06}, {W, -0.06}};
                for (int i = 0; i <= 16; ++i) {
                    const real u = W - 2.0 * W * i / 16;
                    pts.push_back({u, 0.035 - 0.022 * dip(u) + 0.01 * std::exp(-std::pow((t - 0.3) / 0.2, 2.0))});
                }
                return pts;
            }, 0.05, bodyNodes);
            for (real zr : {-place, place}) {
                const Vec3 hc = rA + rUp * 0.67 + Vec3{0, 0, zr};
                vb.pillow("fabric", hc + Vec3{0, 0, -0.12}, hc + Vec3{0, 0, 0.12}, rFwd, rUp, [](real) {
                    std::vector<std::pair<real, real>> pts;
                    for (int i = 0; i < 14; ++i) {
                        const real a = 2.0 * kPi * i / 14;
                        pts.push_back({0.042 * std::cos(a), 0.065 * std::sin(a)});
                    }
                    return pts;
                }, 0.035, bodyNodes, 3);
                for (real r : {-0.055, 0.055})
                    vb.tube("seat_frame", rA + rUp * 0.54 + Vec3{0, 0, zr + r}, hc - rUp * 0.05 + Vec3{0, 0, r}, 0.006, bodyNodes, 8);
            }
            // Parcel shelf / boot cover behind the backrest.
            const real shelfY = rA.y + rUp.y * 0.56 - 0.01;
            vb.box("interior", {rA.x + rUp.x * 0.56 - 0.24, shelfY, 0}, {0.22, 0.008, W}, bodyNodes);
        }
        // Steering wheel ring (LHD -> driver on the left, -z).
        MeshSurface& m = vb.surf("trim", true);
        const Vec3 c{dashX - 0.22, beltY + 0.02, -0.36};
        const Vec3 ax = normalize(Vec3{-1.0, 0.45, 0.0});
        vis.steeringPivot = vb.skinNearest(c, bodyNodes);
        vis.steeringAxis = ax;
        const Vec3 u{0, 0, 1};
        const Vec3 v = cross(ax, u);
        const int seg = 48, ring = 10;
        const real Rw = 0.18, rw = 0.016;
        std::vector<std::uint32_t> ids;
        for (int i = 0; i <= seg; ++i) {
            const real a = 2.0 * kPi * i / seg;
            const Vec3 dir = u * std::cos(a) + v * std::sin(a);
            for (int j = 0; j < ring; ++j) {
                const real b = 2.0 * kPi * j / ring;
                const Vec3 p = c + dir * (Rw + rw * std::cos(b)) + ax * (rw * std::sin(b));
                ids.push_back(vb.vertex(m, p, vb.skinNearest(p, bodyNodes)));
            }
        }
        for (int i = 0; i < seg; ++i)
            for (int j = 0; j < ring; ++j) {
                const int jn = (j + 1) % ring;
                const std::uint32_t a = ids[static_cast<std::size_t>(i * ring + j)], b = ids[static_cast<std::size_t>(i * ring + jn)];
                const std::uint32_t c2 = ids[static_cast<std::size_t>((i + 1) * ring + j)], d = ids[static_cast<std::size_t>((i + 1) * ring + jn)];
                VisBuilder::tri(m, a, c2, d);
                VisBuilder::tri(m, a, d, b);
            }
        vb.bevelBox("interior", c, {0.026, 0.047, 0.075}, 0.022, bodyNodes, ax, v, u, true);
        vb.bevelBox("trim", c - ax * 0.012, {0.014, 0.018, 0.16}, 0.012, bodyNodes, ax, v, u, true);
        vb.bevelBox("trim", c - ax * 0.012 - v * 0.084, {0.013, 0.084, 0.020}, 0.011, bodyNodes, ax, v, u, true);
        vb.box("chrome", c + ax * 0.027, {0.002, 0.011, 0.014}, bodyNodes, ax, v, u, true);
        for (real side : {-1.0, 1.0}) {
            vb.box("chrome", c + ax * 0.005 + u * (side * 0.113), {0.006, 0.011, 0.030}, bodyNodes, ax, v, u, true);
            vb.box("seam", c + ax * 0.015 + u * (side * 0.112), {0.004, 0.008, 0.015}, bodyNodes, ax, v, u, true);
        }
    }

    // ---- underbody: exhaust, heat shield, rails, crossmembers, subframe, pipes, spare wheel well
    {
        const real yF = [&] { return prof.yBottom(0.5 * (prof.xFA + prof.xRA)); }();
        const real archF = prof.xFA - prof.Ra - 0.04, archR = prof.xRA + prof.Ra + 0.04;
        Vec3 tank{0.5 * (prof.xFA + prof.xRA) - 0.55, yF + 0.05, 0.0};
        if (rig.fuelTank.size() == 4) {
            tank = Vec3{0, 0, 0};
            for (std::uint32_t n : rig.fuelTank) tank += body.positions()[n];
            tank = tank / 4.0;
        }
        // Exhaust: down-pipe at the engine, catalytic converter and pipe in the tunnel, past the
        // tank, centre silencer, kick-up over the rear axle, transverse rear silencer, tailpipe.
        const real zt = -0.55 * hw;
        const real xTankF = tank.x + 0.34, xTankR = tank.x - 0.34;
        const real yP = yF - 0.012;
        // An electric car has no exhaust at all.
        if (build.def.engine.type != "electric") {
            const std::vector<Vec3> path{
                {prof.xFA + 0.05, prof.yBottom(prof.xFA) + 0.16, 0.10}, {prof.xFA - 0.12, yP + 0.02, 0.06},
                {prof.xCowl - 0.30, yP, 0.03}, {xTankF + 0.10, yP, 0.03}, {xTankF - 0.05, yP, -0.42},
                {xTankR - 0.02, yP, -0.42}, {archR + 0.02, yP, -0.40}, {prof.xRA + 0.05, yP + 0.09, -0.40},
                {prof.xRA - prof.Ra - 0.02, yP + 0.05, -0.38}};
            for (std::size_t i = 0; i + 1 < path.size(); ++i) {
                const Vec3 d = normalize(path[i + 1] - path[i]);
                vb.tube("exhaust", path[i] - d * 0.012, path[i + 1] + d * 0.012, 0.026, bodyNodes, 10);
            }
            for (std::size_t i = 1; i + 1 < path.size(); ++i) vb.oval("exhaust", path[i], {0.027, 0.027, 0.027}, bodyNodes);
            {
                const Vec3 a = path[1] + normalize(path[2] - path[1]) * 0.08;
                vb.pillow("exhaust", a, a + normalize(path[2] - path[1]) * 0.34, {0, 0, 1}, {0, 1, 0}, [](real) {
                    std::vector<std::pair<real, real>> pts;
                    for (int i = 0; i < 14; ++i) { const real t = 2.0 * kPi * i / 14; pts.push_back({0.085 * std::cos(t), 0.045 * std::sin(t)}); }
                    return pts;
                }, 0.05, bodyNodes, 3);  // catalytic converter
                const Vec3 sc{0.5 * (xTankR + archR), yP, -0.41};
                vb.pillow("exhaust", sc + Vec3{0.16, 0, 0}, sc - Vec3{0.16, 0, 0}, {0, 0, 1}, {0, 1, 0}, [](real) {
                    std::vector<std::pair<real, real>> pts;
                    for (int i = 0; i < 16; ++i) { const real t = 2.0 * kPi * i / 16; pts.push_back({0.075 * std::cos(t), 0.055 * std::sin(t)}); }
                    return pts;
                }, 0.04, bodyNodes, 3);  // centre silencer
            }
            const real xBox = std::max<real>(0.22, prof.xRA - prof.Ra - 0.20);
            const Vec3 boxC{xBox, prof.yBottom(xBox) + 0.04, zt * 0.55};
            vb.pillow("exhaust", boxC + Vec3{0, 0, 0.24}, boxC - Vec3{0, 0, 0.24}, {1, 0, 0}, {0, 1, 0}, [](real) {
                std::vector<std::pair<real, real>> pts;
                for (int i = 0; i < 18; ++i) {
                    const real t = 2.0 * kPi * i / 18, c = std::cos(t), sn = std::sin(t);
                    pts.push_back({0.13 * std::copysign(std::pow(std::abs(c), 0.7), c), 0.06 * std::copysign(std::pow(std::abs(sn), 0.7), sn)});
                }
                return pts;
            }, 0.05, bodyNodes, 4);  // rear silencer
            vb.tube("exhaust", path.back(), boxC + Vec3{0.08, 0.0, 0.20}, 0.026, bodyNodes, 10);
            const Vec3 tipA = boxC + Vec3{-0.06, -0.01, -0.21};
            vb.tube("exhaust", tipA, {0.04, prof.yBottom(0.04) + 0.05, zt}, 0.026, bodyNodes, 10);
            vb.tube("chrome", {0.075, prof.yBottom(0.04) + 0.05, zt}, {-0.012, prof.yBottom(0.04) + 0.05, zt}, 0.036, bodyNodes, 16);
            vb.tube("seam", {-0.010, prof.yBottom(0.04) + 0.05, zt}, {-0.013, prof.yBottom(0.04) + 0.05, zt}, 0.030, bodyNodes, 16);
        }
        // Ribbed heat shield over the tunnel section of the pipe.
        {
            std::vector<std::vector<Vec3>> rows;
            for (int i = 0; i <= 10; ++i) {
                const real x = prof.xCowl - 0.28 - (prof.xCowl - 0.28 - (xTankF + 0.12)) * i / 10;
                std::vector<Vec3> row;
                for (int j = 0; j <= 12; ++j) {
                    const real z = 0.03 - 0.14 + 0.28 * j / 12;
                    row.push_back({x, yF - 0.012 - 0.007 * std::abs(std::sin(kPi * j / 2.0)), z});
                }
                rows.push_back(row);
            }
            vb.sheet("heatshield", rows, {0, -1, 0}, bodyNodes);
        }
        // Longitudinal rails and crossmembers between the wheel arches.
        for (real side : {-1.0, 1.0}) {
            const real zr = side * (prof.zIn(0.5 * (archF + archR)) - 0.06);
            vb.bevelBox("underbody", {0.5 * (archF + archR), yF - 0.022, zr}, {0.5 * (archF - archR), 0.024, 0.04}, 0.012, bodyNodes);
            for (real x : {archR + 0.30, archF - 0.35, archF - 0.10})
                vb.box("underbody", {x, yF - 0.026, side * 0.02 + side * (prof.halfW(x) - 0.10) * 0.5}, {0.03, 0.008, 0.020}, bodyNodes);
        }
        for (real x : {prof.xB + 0.05, prof.xB + 0.40, archR + 0.12})
            vb.bevelBox("underbody", {x, yF - 0.016, 0.0}, {0.035, 0.016, prof.zIn(x) - 0.08}, 0.01, bodyNodes);
        // Front subframe under the engine.
        {
            const real ys = prof.yBottom(prof.xFA) + 0.04;
            for (real side : {-1.0, 1.0})
                vb.bevelBox("chassis", {prof.xFA + 0.03, ys, side * 0.33}, {0.36, 0.03, 0.035}, 0.012, bodyNodes);
            for (real x : {prof.xFA - 0.28, prof.xFA + 0.25})
                vb.bevelBox("chassis", {x, ys, 0}, {0.035, 0.028, 0.36}, 0.012, bodyNodes);
        }
        // Brake and fuel lines along the right-hand rail.
        for (int k = 0; k < 3; ++k) {
            const real z = prof.zIn(0.5 * (archF + archR)) - 0.12 - 0.012 * k;
            vb.tube(k == 2 ? "exhaust" : "chrome", {archF + 0.02, yF - 0.008, z}, {archR - 0.02, yF - 0.008, z}, k == 2 ? 0.006 : 0.0035, bodyNodes, 6);
        }
        // Spare wheel well pressed into the boot floor, if the overhang leaves room.
        const real xWell = prof.xRA - prof.Ra - 0.34;
        if (xWell > 0.42) {
            const real yw = prof.yBottom(xWell);
            vb.tube("underbody", {xWell, yw + 0.01, 0.12}, {xWell, yw - 0.07, 0.12}, 0.27, bodyNodes, 24);
        }
    }

    // Telescoping support bodies and polished rods follow the real bonnet
    // actuator endpoints. They disappear with the procedural body on imported cars.
    for (std::size_t side = 0; side < build.layout.bonnetStrutBeams.size(); ++side) {
        const Beam& support = body.beams()[build.layout.bonnetStrutBeams[side]];
        const auto reference = build.layout.bonnetNodes[side];
        const real restLength = length(body.positions()[support.b] - body.positions()[support.a]);
        const real casingLength = restLength * 0.70;
        const real fullStrokeLength = restLength * (1.0 + support.hydroRatio);
        const real rodLength = std::max(restLength * 0.35, fullStrokeLength - casingLength + 0.06);
        vb.strut("chassis", support.a, support.b, reference, 0.012, 10, 0, 0, 0.025, casingLength);
        vb.strut("chrome", support.a, support.b, reference, 0.006, 10, 1, 1, -rodLength, -0.015);
    }

    // ---- chassis parts (suspension, engine, radiator, tank, shafts)
    for (const CarCorner& cn : rig.corners) {
        vb.strut("chassis", cn.lowerF, cn.lbj, cn.lowerR, 0.016);
        vb.strut("chassis", cn.lowerR, cn.lbj, cn.lowerF, 0.016);
        vb.strut("chassis", cn.upperF, cn.ubj, cn.upperR, 0.012);
        vb.strut("chassis", cn.upperR, cn.ubj, cn.upperF, 0.012);
        vb.strut("chassis", cn.rackEnd, cn.steerArm, cn.lbj, 0.010);
        vb.strut("chassis", cn.arbEnd, cn.armMid, cn.arbPivot, 0.008, 6);
        vb.strut("chassis", cn.arbPivot, cn.arbEnd, cn.lowerF, 0.011, 6);
        const real len = length(body.positions()[cn.tower] - body.positions()[cn.armMid]);
        vb.coil("spring", cn.armMid, cn.tower, cn.lbj, 0.052, 0.0085, 6.5, 0.10, 0.92);
        vb.strut("chassis", cn.armMid, cn.tower, cn.lbj, 0.024, 10, 0.0, 0.0, 0.02, 0.55 * len);
        vb.strut("chrome", cn.armMid, cn.tower, cn.lbj, 0.009, 8, 1.0, 1.0, -0.45 * len, -0.01);
        const std::vector<std::uint32_t> upr = {cn.hubIn, cn.hubOut, cn.lbj, cn.ubj, cn.steerArm};
        const Vec3 hin = body.positions()[cn.hubIn];
        const Vec3 hout = body.positions()[cn.hubOut];
        const Vec3 hc = (hin + hout) * 0.5;
        vb.box("chassis", (hin + body.positions()[cn.lbj] + body.positions()[cn.ubj]) / 3.0, {0.05, 0.13, 0.03}, upr);
        const real sgn = cn.right ? 1.0 : -1.0;
        vb.box("caliper", {hc.x - 0.04, hc.y + 0.13, hc.z - sgn * 0.045}, {0.07, 0.05, 0.03}, upr);
    }
    for (int axle = 0; axle < 2; ++axle) {
        const CarCorner& l = rig.corners[static_cast<std::size_t>(axle * 2)];
        const CarCorner& r = rig.corners[static_cast<std::size_t>(axle * 2 + 1)];
        vb.strut("chassis", l.arbPivot, r.arbPivot, l.arbEnd, 0.011, 6);
        vb.strut("chassis", l.rackEnd, r.rackEnd, l.lowerF, 0.022, 8);
    }
    if (rig.engine.size() == 8) {
        Vec3 c{0, 0, 0};
        for (std::uint32_t n : rig.engine) c += body.positions()[n];
        c = c / 8.0;
        const Vec3 lo = body.positions()[rig.engine[0]], hi = body.positions()[rig.engine[7]];
        const Vec3 h = (hi - lo) * 0.5;
        vb.box("engine", c, {std::abs(h.x) * 0.92, std::abs(h.y) * 0.9, std::abs(h.z) * 0.95}, rig.engine);
        const real top = c.y + std::abs(h.y) * 0.95;
        const real ex = std::abs(h.x), ez = std::abs(h.z);
        // Cast cylinder head, gasket seam and ribbed composite cam cover.
        vb.box("chrome", {c.x, top - 0.045, c.z}, {ex * 0.94, 0.045, ez * 0.86}, rig.engine);
        vb.box("seam", {c.x, top + 0.003, c.z}, {ex * 0.89, 0.006, ez * 0.78}, rig.engine);
        vb.box("trim", {c.x, top + 0.027, c.z}, {ex * 0.86, 0.021, ez * 0.74}, rig.engine);
        for (int rib = 0; rib < 6; ++rib)
            vb.box("engine", {c.x - ex * 0.64 + rib * ex * 0.25, top + 0.051, c.z}, {0.008, 0.004, ez * 0.55}, rig.engine);
        const int cylinders = std::clamp(build.def.engine.cylinders, 2, 8);
        for (int cylinder = 0; cylinder < cylinders; ++cylinder) {
            const real x = c.x - ex * 0.72 + (1.44 * ex * cylinder) / (cylinders - 1);
            // Coil packs, fasteners and individual curved intake runners.
            vb.box("trim", {x, top + 0.055, -ez * 0.48}, {0.018, 0.009, 0.026}, rig.engine);
            vb.tube("chrome", {x, top + 0.052, ez * 0.55}, {x, top + 0.060, ez * 0.55}, 0.008, rig.engine, 6);
            const Vec3 port{x, top - 0.04, ez * 0.82};
            const Vec3 elbow{x, top + 0.025, ez + 0.085};
            vb.tube("engine", port, elbow, 0.023, rig.engine);
            vb.tube("engine", elbow, {x, top - 0.07, ez + 0.16}, 0.023, rig.engine);
        }
        vb.tube("trim", {c.x - ex, top - 0.075, ez + 0.16}, {c.x + ex, top - 0.075, ez + 0.16}, 0.045, rig.engine);
        // Oil filler cap and dipstick handle remain recognisable under an open hood.
        vb.tube("trim", {c.x + ex * 0.6, top + 0.044, 0.04}, {c.x + ex * 0.6, top + 0.065, 0.04}, 0.032, rig.engine);
        vb.tube("spring", {c.x - ex * 0.8, top - 0.03, -ez - 0.012}, {c.x - ex * 0.8, top + 0.035, -ez - 0.012}, 0.012, rig.engine);
        // Accessory belt cover, crank pulley and alternator housing.
        vb.box("trim", {c.x + ex + 0.018, c.y, 0}, {0.018, std::abs(h.y) * 0.88, ez * 0.83}, rig.engine);
        vb.tube("chassis", {c.x + ex + 0.038, c.y - 0.08, 0}, {c.x + ex + 0.063, c.y - 0.08, 0}, 0.09, rig.engine, 20);
        vb.tube("engine", {c.x + ex - 0.06, c.y + 0.07, -ez * 0.7}, {c.x + ex + 0.055, c.y + 0.07, -ez * 0.7}, 0.065, rig.engine, 16);
        // Body-mounted battery and airbox must not follow a detached engine.
        const real trayX = prof.xCowl + 0.30;
        const real trayZ = std::min<real>(prof.shoulderHalf(trayX) - 0.17, 0.59);
        const real trayY = std::min(top - 0.04, bd.hoodHeight - 0.20);
        vb.box("chassis", {trayX, trayY - 0.075, -trayZ}, {0.145, 0.014, 0.11}, bodyNodes);
        vb.box("trim", {trayX, trayY, -trayZ}, {0.125, 0.065, 0.095}, bodyNodes);
        vb.box("engine", {trayX, trayY + 0.068, -trayZ}, {0.13, 0.009, 0.10}, bodyNodes);
        for (real side : {-1.0, 1.0})
            vb.tube(side < 0 ? "spring" : "chrome", {trayX + side * 0.085, trayY + 0.075, -trayZ},
                    {trayX + side * 0.085, trayY + 0.092, -trayZ}, 0.014, bodyNodes);
        vb.box("trim", {trayX, trayY - 0.015, trayZ}, {0.15, 0.075, 0.11}, bodyNodes);
        for (int rib = 0; rib < 7; ++rib)
            vb.box("chassis", {trayX - 0.12 + rib * 0.04, trayY + 0.064, trayZ}, {0.005, 0.004, 0.095}, bodyNodes);
        // Sheet-metal firewall and chassis rails close the engine compartment.
        vb.box("chassis", {prof.xCowl + 0.018, top - 0.13, 0}, {0.018, 0.18, prof.shoulderHalf(prof.xCowl) * 0.87}, bodyNodes);
        for (real side : {-1.0, 1.0}) {
            vb.box("paint", {(prof.xCowl + L - 0.12) * 0.5, top - 0.22, side * 0.46},
                   {(L - 0.12 - prof.xCowl) * 0.5, 0.045, 0.045}, bodyNodes);
            const auto& tower = rig.corners[side < 0 ? 0 : 1];
            const Vec3 p = body.positions()[tower.tower];
            vb.tube("paint", p - Vec3{0, 0.09, 0}, p + Vec3{0, 0.018, 0}, 0.105, bodyNodes, 20);
            vb.tube("chassis", p + Vec3{0, 0.019, 0}, p + Vec3{0, 0.029, 0}, 0.046, bodyNodes);
        }
        if (rig.oilPan.size() == 2) {
            std::vector<std::uint32_t> pc = rig.oilPan;
            pc.push_back(rig.engine[0]);
            pc.push_back(rig.engine[4]);
            const Vec3 pm = (body.positions()[rig.oilPan[0]] + body.positions()[rig.oilPan[1]]) * 0.5;
            vb.box("chassis", pm + Vec3{0, 0.045, 0}, {0.20, 0.045, 0.16}, pc);
        }
    }
    if (rig.radiator.size() == 4) {
        Vec3 c{0, 0, 0};
        for (std::uint32_t n : rig.radiator) c += body.positions()[n];
        c = c / 4.0;
        const Vec3 d = body.positions()[rig.radiator[3]] - body.positions()[rig.radiator[0]];
        vb.box("radiator", c, {0.025, std::abs(d.y) * 0.5, std::abs(d.z) * 0.5}, rig.radiator);
        // Aluminium cooling fins, side tanks and visible rear fan shroud.
        for (int fin = 0; fin < 17; ++fin) {
            const real y = c.y - std::abs(d.y) * 0.46 + fin * std::abs(d.y) * 0.92 / 16.0;
            vb.box("engine", {c.x + 0.028, y, c.z}, {0.004, 0.002, std::abs(d.z) * 0.44}, rig.radiator);
        }
        for (real side : {-1.0, 1.0})
            vb.box("trim", {c.x, c.y, side * std::abs(d.z) * 0.47}, {0.032, std::abs(d.y) * 0.51, 0.025}, rig.radiator);
        const real fanR = std::min(std::abs(d.y) * 0.43, std::abs(d.z) * 0.38);
        vb.tube("trim", c - Vec3{0.047, 0, 0}, c - Vec3{0.029, 0, 0}, fanR, rig.radiator, 24);
        vb.tube("engine", c - Vec3{0.061, 0, 0}, c - Vec3{0.048, 0, 0}, fanR * 0.22, rig.radiator);
        for (int blade = 0; blade < 7; ++blade) {
            const real angle = 2.0 * kPi * blade / 7.0;
            const Vec3 radial{0, std::cos(angle), std::sin(angle)};
            vb.box("chassis", c - Vec3{0.054, 0, 0} + radial * (fanR * 0.57), {0.008, fanR * 0.32, fanR * 0.12},
                   rig.radiator, {1, 0, 0}, radial, cross(Vec3{1, 0, 0}, radial));
        }
        if (rig.engine.size() == 8) {
            std::vector<std::uint32_t> hoseNodes = rig.radiator;
            hoseNodes.insert(hoseNodes.end(), rig.engine.begin(), rig.engine.end());
            const Vec3 inlet = c + Vec3{-0.04, std::abs(d.y) * 0.34, std::abs(d.z) * 0.43};
            const Vec3 outlet = body.positions()[rig.engine[7]] + Vec3{0.01, -0.07, 0.01};
            const Vec3 elbow{(inlet.x + outlet.x) * 0.5, inlet.y, inlet.z};
            vb.tube("tire", inlet, elbow, 0.023, hoseNodes);
            vb.tube("tire", elbow, outlet, 0.023, hoseNodes);
        }
    }
    if (rig.fuelTank.size() == 4) {
        Vec3 c{0, 0, 0};
        for (std::uint32_t n : rig.fuelTank) c += body.positions()[n];
        c = c / 4.0;
        vb.bevelBox("tank", c + Vec3{0, 0.05, 0}, {0.30, 0.08, 0.36}, 0.04, rig.fuelTank);
        for (real dx : {-0.16, 0.16})
            vb.box("chassis", c + Vec3{dx, -0.032, 0}, {0.018, 0.003, 0.37}, rig.fuelTank);  // straps
        vb.tube("tire", c + Vec3{-0.05, 0.10, 0.30}, c + Vec3{-0.30, 0.25, 0.62 * prof.hw}, 0.022, rig.fuelTank, 10);  // filler hose
    }
    if (rig.diff >= 0 && rig.engine.size() == 8) {
        const auto d = static_cast<std::uint32_t>(rig.diff);
        vb.strut("chassis", rig.engine[0], d, rig.engine[1], 0.028, 8, 0.0, 1.0, 0.0, 0.0);
        vb.box("chassis", body.positions()[d], {0.12, 0.10, 0.13}, {d, rig.corners[2].lowerF, rig.corners[3].lowerF});
        for (int c = 2; c < 4; ++c)
            vb.strut("chassis", d, rig.corners[static_cast<std::size_t>(c)].hubIn, rig.corners[static_cast<std::size_t>(c)].lbj, 0.018, 6);
    }
    if (build.def.engine.layout != "RWD" && rig.engine.size() == 8) {
        for (int c = 0; c < 2; ++c) {
            const CarCorner& cn = rig.corners[static_cast<std::size_t>(c)];
            vb.strut("chassis", rig.engine[cn.right ? 5 : 4], cn.hubIn, cn.lbj, 0.018, 6);
        }
    }

    // ---- lamps per side (each corner's lamp breaks and goes dark on its own)
    {
        std::vector<MeshSurface> split;
        for (MeshSurface& m : vis.skinned) {
            const std::string& mat = m.material;
            const auto endsWith = [&](const char* tail) {
                const std::size_t n = std::char_traits<char>::length(tail);
                return mat.size() >= n && mat.compare(mat.size() - n, n, tail) == 0;
            };
            const bool lamp = endsWith("headlight") || endsWith("taillight") || endsWith("reverselight");
            if (!lamp || m.side != 0) continue;
            MeshSurface halves[2];
            std::vector<std::uint32_t> remap[2];
            for (int h = 0; h < 2; ++h) {
                halves[h].material = m.material;
                halves[h].doubleSided = m.doubleSided;
                halves[h].side = h == 0 ? -1 : 1;
                remap[h].assign(m.skin.size(), 0xffffffffu);
            }
            for (std::size_t t = 0; t + 2 < m.indices.size(); t += 3) {
                const real z = (m.positions[m.indices[t] * 3 + 2] + m.positions[m.indices[t + 1] * 3 + 2] +
                                m.positions[m.indices[t + 2] * 3 + 2]) / 3.0;
                const int h = z < 0.0 ? 0 : 1;
                for (int k = 0; k < 3; ++k) {
                    const std::uint32_t v = m.indices[t + static_cast<std::size_t>(k)];
                    if (remap[h][v] == 0xffffffffu) {
                        remap[h][v] = static_cast<std::uint32_t>(halves[h].skin.size());
                        for (int c = 0; c < 3; ++c) halves[h].positions.push_back(m.positions[v * 3 + static_cast<std::uint32_t>(c)]);
                        halves[h].skin.push_back(m.skin[v]);
                    }
                    halves[h].indices.push_back(remap[h][v]);
                }
            }
            m.material.clear();  // replaced by the halves below
            for (MeshSurface& half : halves)
                if (!half.indices.empty()) split.push_back(std::move(half));
        }
        vis.skinned.erase(std::remove_if(vis.skinned.begin(), vis.skinned.end(),
                                         [](const MeshSurface& m) { return m.material.empty(); }),
                          vis.skinned.end());
        for (MeshSurface& m : split) vis.skinned.push_back(std::move(m));
    }

    // ---- glass panes (windscreen, rear window, side glass crack and shatter separately)
    {
        std::vector<MeshSurface> panes;
        for (MeshSurface& m : vis.skinned) {
            if (m.material == "door_left_glass") m.pane = 3;
            if (m.material == "door_right_glass") m.pane = 4;
            if (m.material == "rdoor_left_glass") m.pane = 3;
            if (m.material == "rdoor_right_glass") m.pane = 4;
            if (m.material == "tailgate_glass") m.pane = 2;
            if (m.material != "glass" || m.pane != 0) continue;
            MeshSurface parts[4];
            std::vector<std::uint32_t> remap[4];
            for (int h = 0; h < 4; ++h) {
                parts[h].material = m.material;
                parts[h].doubleSided = m.doubleSided;
                parts[h].pane = static_cast<std::int8_t>(h + 1);
                remap[h].assign(m.skin.size(), 0xffffffffu);
            }
            auto P = [&](std::uint32_t v) {
                return Vec3{m.positions[v * 3], m.positions[v * 3 + 1], m.positions[v * 3 + 2]};
            };
            for (std::size_t t = 0; t + 2 < m.indices.size(); t += 3) {
                const Vec3 a = P(m.indices[t]), b = P(m.indices[t + 1]), c = P(m.indices[t + 2]);
                const Vec3 n = cross(b - a, c - a);
                const Vec3 centre = (a + b + c) / 3.0;
                int h;
                if (std::abs(n.z) > 0.8 * length(n)) h = centre.z < 0.0 ? 2 : 3;
                else h = centre.x > prof.xB ? 0 : 1;
                for (int k = 0; k < 3; ++k) {
                    const std::uint32_t v = m.indices[t + static_cast<std::size_t>(k)];
                    if (remap[h][v] == 0xffffffffu) {
                        remap[h][v] = static_cast<std::uint32_t>(parts[h].skin.size());
                        for (int q = 0; q < 3; ++q) parts[h].positions.push_back(m.positions[v * 3 + static_cast<std::uint32_t>(q)]);
                        parts[h].skin.push_back(m.skin[v]);
                    }
                    parts[h].indices.push_back(remap[h][v]);
                }
            }
            m.material.clear();
            for (MeshSurface& part : parts)
                if (!part.indices.empty()) panes.push_back(std::move(part));
        }
        vis.skinned.erase(std::remove_if(vis.skinned.begin(), vis.skinned.end(),
                                         [](const MeshSurface& m) { return m.material.empty(); }),
                          vis.skinned.end());
        for (MeshSurface& m : panes) vis.skinned.push_back(std::move(m));
    }

    // ---- rest normals
    for (MeshSurface& m : vis.skinned) computeNormals(m.positions, m.indices, m.normals);

    // ---- wheels
    vis.wheelFront = buildWheelMeshes(build.def.tires, bd.style);
    if (build.def.tires.widthRear > 0.0 && build.def.tires.widthRear != build.def.tires.width) {
        TireDef rear = build.def.tires;
        rear.width = rear.widthRear;
        vis.wheelRear = buildWheelMeshes(rear, bd.style);
    } else {
        vis.wheelRear = vis.wheelFront;
    }

    // ---- camera anchors
    {
        const real ex = prof.xB + 0.12 + bd.seatShift;
        const real ey = std::min(bd.beltHeight + 0.29, prof.yRoofRail(ex) - 0.10);
        vis.driverEye = vb.skinNearest({ex, ey, -0.36}, bodyNodes);
        vis.chaseTarget = vb.skinNearest({0.5 * (prof.xFA + prof.xRA), 0.5 * bd.height + 0.2, 0.0}, bodyNodes);
    }
}

}  // namespace sb
