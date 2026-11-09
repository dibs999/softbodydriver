// Fixed-speed chassis measurement rig. No render/camera filtering and no physics tuning.
#include "sbcore/sbcore.hpp"
#include "stability_metrics.hpp"
#include <nlohmann/json.hpp>
#include <array>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>

using nlohmann::json;
namespace fs = std::filesystem;
namespace {
#ifdef __VERSION__
constexpr const char* compiler = __VERSION__;
#else
constexpr const char* compiler = "C++20 compiler (see build metadata)";
#endif
constexpr double dt = 0.0005, settleSeconds = 3, warmSeconds = 2, measureSeconds = 10;
struct Range {
    double minimum = std::numeric_limits<double>::infinity(), maximum = -minimum, sum = 0, square = 0;
    std::size_t count = 0;
    void add(double x) { minimum = std::min(minimum, x); maximum = std::max(maximum, x); sum += x; square += x*x; ++count; }
    json report() const {
        const double mean = sum / static_cast<double>(count);
        return {{"min",minimum},{"max",maximum},{"mean",mean},
            {"stddev",std::sqrt(std::max(0.0,square/static_cast<double>(count)-mean*mean))}};
    }
};
std::string fingerprint(const fs::path& file) {
    std::ifstream input(file, std::ios::binary);
    std::uint64_t hash = 14695981039346656037ULL;
    for (char c; input.get(c);) { hash ^= static_cast<unsigned char>(c); hash *= 1099511628211ULL; }
    std::ostringstream out; out << std::hex << hash; return out.str();
}
json run(const fs::path& path, double targetKmh, const std::string& mode, const fs::path& output) {
    const auto started = std::chrono::steady_clock::now();
    auto build = sb::buildCar(sb::loadCarDefinition(path.string()));
    const auto layout = build.layout;
    sb::World world;
    world.addCollider(sb::StaticCollider::plane({0,0,0},{0,1,0},1.0,"flat asphalt"));
    world.addBody(std::move(build.body));
    auto& car = world.body(0);
    sb::VehicleControls controls;
    controls.gear = mode=="powered" ? -99 : 0; controls.ignition = mode=="powered"; controls.steer = 0;
    car.setControls(controls);
    world.simulate(settleSeconds);
    const auto settled = car.stats();
    const double speed = targetKmh / 3.6;
    const std::string stem = build.def.id + "_" + std::to_string(static_cast<int>(targetKmh)) + "_" + mode;
    double accelerationSeconds = 0;
    if (mode=="powered") {
        std::ofstream acceleration(output/(stem+"_acceleration.csv"));
        acceleration << std::setprecision(12) << "time_s,speed_kmh,engine_rpm,gear,throttle,yaw_deg,lateral_displacement_m,broken_beams\n";
        controls.throttle=1; car.setControls(controls);
        double peak=0;
        for (int sample=0; sample<3000; ++sample) {
            world.simulate(.02); accelerationSeconds+=.02;
            const auto telemetry=car.telemetry(); peak=std::max(peak,telemetry.speedKmh);
            const auto& p=car.positions();
            const auto forward=sb::normalize(p[layout.refFL]+p[layout.refFR]-p[layout.refRL]-p[layout.refRR]);
            acceleration << accelerationSeconds << ',' << telemetry.speedKmh << ',' << telemetry.engineRpm << ','
                << telemetry.gear << ",1," << std::atan2(forward.z,forward.x)*180/stability::pi << ','
                << car.centerOfMass().z << ',' << telemetry.brokenBeams << '\n';
            if (!world.stats().finite) throw std::runtime_error(stem+": non-finite acceleration state");
            if (telemetry.speedKmh>=targetKmh*.99) break;
        }
        if (!acceleration) throw std::runtime_error("failed writing acceleration CSV");
        if (peak<targetKmh*.99) {
            const auto telemetry=car.telemetry();
            json result{{"car",build.def.id},{"target_kmh",targetKmh},{"mode",mode},{"pass",false},
                {"target_reached",false},{"measurement_status","target_unattained_not_validated"},{"constant_speed_window_valid",false},{"hf_limits_pass",nullptr},
                {"reason","normal full-throttle powertrain did not reach99% oftarget within60s;10s target-speed measurement not performed"},
                {"acceleration_seconds",accelerationSeconds},{"peak_kmh",peak},{"terminal_kmh",telemetry.speedKmh},
                {"terminal_engine_rpm",telemetry.engineRpm},{"terminal_gear",telemetry.gear},
                {"terminal_engine_power_W",car.powertrain().lastEnginePower()},
                {"broken_beams",telemetry.brokenBeams},{"deformed_beams",telemetry.deformedBeams},
                {"finite",world.stats().finite},{"raw_csv",stem+"_acceleration.csv"}};
            std::cout << stem << " target not reached: peak " << peak << " km/h in60s; NOT VALIDATED" << std::endl;
            return result;
        }
    } else {
        car.setVelocity({speed,0,0});
        // Same rolling initialization as the existing highway handling regressions.
        for (const auto& wheel : car.wheels()) {
            const auto center = wheel.center(car), axis = wheel.axis(car);
            for (auto node : wheel.treadNodes)
                car.velocities()[node] += sb::cross(axis,car.positions()[node]-center) * (speed/wheel.spec.radius);
        }
    }
    double cruiseIntegral=.2;
    std::size_t cruiseTicks=0;
    const auto tick = [&]() {
        if (mode == "tow") {
            // Distributed ideal tow: change only uniform +X translation. Relative
            // node velocities, angular motion, Y/Z velocity and positions are untouched.
            car.addVelocity({speed-car.centerOfMassVelocity().x,0,0});
        }
        if (mode=="powered" && cruiseTicks++ % 40 == 0) {
            const double error=targetKmh-car.telemetry().speedKmh;
            cruiseIntegral=std::clamp(cruiseIntegral+error*.015*.02,0.0,1.0);
            controls.throttle=std::clamp(cruiseIntegral+.08*error,0.0,1.0);
            controls.brake=std::clamp((-error-2)*.03,0.0,.3);
            car.setControls(controls);
        }
        world.step();
    };
    for (int i = 0; i < static_cast<int>((mode=="powered" ? 10.0 : warmSeconds)/dt); ++i) tick();
    const auto warm = car.stats();
    std::ofstream raw(output/(stem+".csv"));
    raw << std::setprecision(12);
    raw << "time_s,speed_kmh,chassis_y_m,roll_deg,pitch_deg,chassis_vy_m_s,yaw_deg,lateral_velocity_m_s,lateral_displacement_m,throttle,brake,gear,engine_rpm";
    for (const auto& wheel : car.wheels()) raw << ',' << wheel.spec.name << "_normal_force_N," << wheel.spec.name << "_estimated_load_N";
    raw << '\n';
    std::vector<double> y, roll, pitch;
    std::array<Range,4> load, estimatedLoad;
    Range speedRange, yRange, rollRange, pitchRange, vyRange, yawRange, lateralSpeedRange, lateralDisplacementRange;
    const double initialLateral = car.centerOfMass().z;
    bool finite = world.stats().finite;
    std::size_t burstWheels = 0;
    const std::array<std::uint32_t,4> refs{layout.refFL,layout.refFR,layout.refRL,layout.refRR};
    const auto count = static_cast<std::size_t>(measureSeconds/dt);
    y.reserve(count); roll.reserve(count); pitch.reserve(count);
    for (std::size_t sample = 0; sample < count; ++sample) {
        tick();
        for (std::size_t n = 0; n < car.nodeCount(); ++n)
            finite &= sb::isFinite(car.positions()[n]) && sb::isFinite(car.velocities()[n]);
        if (!finite) throw std::runtime_error(stem+": non-finite physics state; raw partial CSV retained");
        const auto& p = car.positions();
        const auto forward = sb::normalize(p[refs[0]]+p[refs[1]]-p[refs[2]]-p[refs[3]]);
        auto right = p[refs[1]]+p[refs[3]]-p[refs[0]]-p[refs[2]];
        right = sb::normalize(right-forward*sb::dot(right,forward));
        const auto up = sb::normalize(sb::cross(right,forward));
        double height = 0, verticalVelocity = 0;
        for (auto ref : refs) { height += p[ref].y*.25; verticalVelocity += car.velocities()[ref].y*.25; }
        double rollAngle = std::atan2(right.y,up.y)*180/stability::pi;
        if (!roll.empty()) { while (rollAngle-roll.back()>180) rollAngle-=360; while (rollAngle-roll.back()<-180) rollAngle+=360; }
        const double pitchAngle = std::atan2(forward.y,std::hypot(forward.x,forward.z))*180/stability::pi;
        const auto velocity = car.centerOfMassVelocity();
        const double kmh = sb::length(velocity)*3.6;
        const double yawAngle = std::atan2(forward.z,forward.x)*180/stability::pi;
        const double lateralDisplacement = car.centerOfMass().z-initialLateral;
        yawRange.add(yawAngle); lateralSpeedRange.add(velocity.z); lateralDisplacementRange.add(lateralDisplacement);
        y.push_back(height); roll.push_back(rollAngle); pitch.push_back(pitchAngle);
        speedRange.add(kmh); yRange.add(height); rollRange.add(rollAngle); pitchRange.add(pitchAngle); vyRange.add(verticalVelocity);
        raw << static_cast<double>(sample+1)*dt << ',' << kmh << ',' << height << ',' << rollAngle << ',' << pitchAngle << ',' << verticalVelocity << ',' << yawAngle << ',' << velocity.z << ',' << lateralDisplacement << ',' << controls.throttle << ',' << controls.brake << ',' << car.powertrain().gear() << ',' << car.powertrain().engineRpm();
        for (std::size_t w = 0; w < car.wheels().size(); ++w) {
            const auto& wheel = car.wheels()[w];
            if (!std::isfinite(wheel.load) || !std::isfinite(wheel.pressurePsi) || !std::isfinite(wheel.tempC) ||
                !std::isfinite(wheel.wear) || !std::isfinite(wheel.angularVelocity))
                throw std::runtime_error(stem+": non-finite wheel state; raw partial CSV retained");
            double normalForce = 0;
            for (auto node : wheel.treadNodes) normalForce += car.contactImpulses()[node].y/dt;
            load[w].add(normalForce); estimatedLoad[w].add(wheel.load);
            raw << ',' << normalForce << ',' << wheel.load;
        }
        raw << '\n';
    }
    if (!raw) throw std::runtime_error("failed writing raw CSV");
    const auto ys = stability::analyze(y,1/dt), rs = stability::analyze(roll,1/dt), ps = stability::analyze(pitch,1/dt);
    std::ofstream spectrum(output/(stem+"_spectrum.csv"));
    spectrum << std::setprecision(12) << "frequency_Hz,vertical_power_m2,roll_power_deg2,pitch_power_deg2\n";
    for (std::size_t k = 0; k < ys.power.size(); ++k)
        spectrum << static_cast<double>(k)*ys.binHz << ',' << ys.power[k] << ',' << rs.power[k] << ',' << ps.power[k] << '\n';
    if (!spectrum) throw std::runtime_error("failed writing spectrum CSV");
    const auto final = car.stats();
    json wheels = json::array();
    for (std::size_t w = 0; w < car.wheels().size(); ++w) {
        const auto& wheel = car.wheels()[w];
        burstWheels += wheel.burst ? 1u : 0u;
        wheels.push_back({{"name",wheel.spec.name},{"normal_force_N",load[w].report()},
            {"estimated_load_N",estimatedLoad[w].report()},{"burst",wheel.burst},{"pressure_psi",wheel.pressurePsi},
            {"temperature_C",wheel.tempC},{"wear",wheel.wear}});
    }
    const bool speedValid = mode!="coast" && speedRange.minimum >= targetKmh*.99 && speedRange.maximum <= targetKmh*1.01;
    const bool hfPass = ys.highRms<.005 && rs.highRms<.15 && ps.highRms<.15;
    const bool pass = (mode=="coast" || speedValid) && finite && final.brokenBeams==0 && final.deformedBeams==0 && burstWheels==0 &&
        ys.highRms<.005 && rs.highRms<.15 && ps.highRms<.15;
    json result{{"car",build.def.id},{"definition",path.string()},{"definition_fnv1a64",fingerprint(path)},
        {"target_kmh",targetKmh},{"mode",mode},{"pass",pass},{"hf_limits_pass",hfPass},
        {"constant_speed_window_valid",speedValid},{"measurement_status",mode=="coast" ? "coasting_diagnostic" : speedValid ? "valid_speed_window" : "invalid_speed_window_not_a_vehicle_hf_failure"},{"finite",finite},{"acceleration_seconds",accelerationSeconds},
        {"yaw_deg",yawRange.report()},{"lateral_velocity_m_s",lateralSpeedRange.report()},
        {"lateral_displacement_m",lateralDisplacementRange.report()},
        {"speed_kmh",speedRange.report()},{"chassis_y_m",yRange.report()},{"roll_deg",rollRange.report()},
        {"pitch_deg",pitchRange.report()},{"chassis_vy_m_s",vyRange.report()},
        {"high_frequency_rms",{{"vertical_mm",ys.highRms*1000},{"roll_deg",rs.highRms},{"pitch_deg",ps.highRms}}},
        {"broken_beams",{{"settled",settled.brokenBeams},{"after_speed_warmup",warm.brokenBeams},{"final",final.brokenBeams}}},
        {"deformed_beams",{{"settled",settled.deformedBeams},{"after_speed_warmup",warm.deformedBeams},{"final",final.deformedBeams}}},
        {"wheels",wheels},{"raw_csv",stem+".csv"},{"spectrum_csv",stem+"_spectrum.csv"},
        {"wall_seconds",std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count()}};
    std::cout << stem << " HF RMS " << ys.highRms*1000 << " mm / " << rs.highRms << " roll deg / " << ps.highRms << " pitch deg; HF " << (hfPass?"PASS":"FAIL") << "; "
        << (mode=="coast" ? "COAST DIAGNOSTIC" : speedValid ? "VALID SPEED WINDOW" : "INVALID SPEED WINDOW") << std::endl;
    return result;
}
}
int main(int argc, char** argv) {
    fs::path output = "stability-results", cars = "game/cars";
    std::string mode = "tow", revision = "unspecified";
    try {
        for (int i=1;i<argc;++i) {
            const std::string arg=argv[i];
            if (arg=="--self-test") { const bool pass=stability::selfTest(); std::cout << "spectral calibration " << (pass?"PASS":"FAIL") << '\n'; return pass?0:1; }
            if (arg=="--help") { std::cout << "stabilitybench [--output DIR] [--cars-dir DIR] [--mode tow|coast|powered] [--revision TEXT]\n"; return 0; }
            if (i+1>=argc) throw std::invalid_argument("missing argument value");
            if(arg=="--output") output=argv[++i]; else if(arg=="--cars-dir") cars=argv[++i];
            else if(arg=="--mode") mode=argv[++i]; else if(arg=="--revision") revision=argv[++i];
            else throw std::invalid_argument("unknown argument: "+arg);
        }
        if(mode!="tow" && mode!="coast" && mode!="powered") throw std::invalid_argument("mode must be tow, coast or powered");
        if(!stability::selfTest()) throw std::runtime_error("spectral calibration failed");
        fs::create_directories(output);
        json report{{"schema",1},{"revision",revision},{"compiler",compiler},{"sample_hz",1/dt},
            {"ground_settle_seconds",settleSeconds},{"speed_warmup_seconds",mode=="powered" ? 10.0 : warmSeconds},{"measurement_seconds",measureSeconds},
            {"sample_count",static_cast<int>(measureSeconds/dt)},{"surface","flat horizontal plane, friction1"},
            {"measurement","unfiltered four safety-cell reference nodes; native solver, no renderer"},
            {"controls",mode=="powered" ? "normal powertrain acceleration from rest, automatic gears,50Hz throttle/brake PI cruise,zero steering; no velocity changes" : "zero steering, neutral, ignition off"},
            {"speed_mode",mode=="tow" ? "uniform world-X velocity correction before each step; angular/Y/Z motion untouched" : mode=="powered" ? "normal powertrain only,60s target acquisition limit,then10s cruise warmup and10s measurement" : "free coast after rolling-speed initialization"},
            {"spectral_method",{{"detrend","least-squares linear trend removed for spectral analysis only"},
                {"window","symmetric Hann, power normalized by sum(window^2)"},{"fft_size",32768},
                {"band_hz",{10,1000}},{"lower_bound_exclusive",true},{"bin_spacing_hz",2000.0/32768},
                {"window_resolution_hz",.1},{"note","zero padding interpolates bins; Hann broadens transitions around10Hz"}}},
            {"validity_note","Tow/powered constant-speed claim requires total measured speed within1% oftarget; HF-pass alone does not establish directional stability. Coast cases report actual speedrange."},
            {"limits",{{"vertical_hf_rms_mm",5},{"roll_hf_rms_deg",.15},{"pitch_hf_rms_deg",.15}}},
            {"cases",json::array()}};
        bool pass=true;
        for(const auto* id:{"kestrel_hatch","concept_gt"}) for(double speed:{50.,100.,160.,200.}) {
            json result;
            try { result=run(cars/(std::string(id)+".car.json"),speed,mode,output); }
            catch (const std::exception& e) {
                const std::string message=e.what();
                result={{"car",id},{"target_kmh",speed},{"mode",mode},{"pass",false},{"error",message}};
                if(message.find("non-finite")!=std::string::npos) result["finite"]=false;
                std::cerr << message << '\n';
            }
            pass &= result["pass"].get<bool>(); report["cases"].push_back(std::move(result));
            std::ofstream file(output/"report.json"); file << report.dump(2) << '\n';
            if(!file) throw std::runtime_error("failed writing JSON report");
        }
        return pass?0:2;
    } catch(const std::exception& e) { std::cerr << "stabilitybench: " << e.what() << '\n'; return 1; }
}
