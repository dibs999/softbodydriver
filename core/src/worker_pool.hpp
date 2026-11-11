// Small persistent worker pool for the physics step: runs f(i) for i in [0, n) on the calling
// thread and a few workers, and returns when every item is done. Built for ~2000 calls per
// second with a handful of items each: workers spin briefly between calls and then sleep on the
// generation counter. One World uses the pool at a time; a second caller runs serially.
#pragma once

#include <atomic>
#include <cstddef>
#include <mutex>
#include <thread>
#include <vector>

namespace sb::detail {

class WorkerPool {
public:
    static WorkerPool& instance();
    /// Stops and joins the workers (call before unloading the library; never during a step).
    static void shutdown();
    ~WorkerPool();

    /// Worker threads besides the caller (0 = run everything on the caller).
    std::size_t workers() const { return threads_.size(); }

    template <class F>
    void run(std::size_t n, F& f) {
        if (n <= 1 || threads_.empty() || !busy_.try_lock()) {
            for (std::size_t i = 0; i < n; ++i) f(i);
            return;
        }
        fn_ = [](void* ctx, std::size_t i) { (*static_cast<F*>(ctx))(i); };
        ctx_ = &f;
        dispatch(n);
        busy_.unlock();
    }

private:
    WorkerPool();
    void dispatch(std::size_t n);
    void work();
    void loop();

    std::vector<std::thread> threads_;
    std::mutex busy_;
    void (*fn_)(void*, std::size_t) = nullptr;
    void* ctx_ = nullptr;
    std::size_t n_ = 0;
    unsigned int fpControl_ = 0;   ///< Caller's SSE control word (denormal / rounding mode) for the job.
    std::atomic<std::size_t> next_{0};
    std::atomic<std::size_t> acks_{0};
    std::atomic<std::uint64_t> generation_{0};
    std::atomic<bool> stop_{false};
};

}  // namespace sb::detail
