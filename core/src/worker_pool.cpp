#include "worker_pool.hpp"

#include <algorithm>
#include <cstdlib>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <immintrin.h>
#define SB_PAUSE() _mm_pause()
#else
#define SB_PAUSE() std::this_thread::yield()
#endif

namespace sb::detail {

namespace {
std::mutex poolMutex;
WorkerPool* pool = nullptr;
}

WorkerPool& WorkerPool::instance() {
    std::lock_guard<std::mutex> lock(poolMutex);
    if (!pool) pool = new WorkerPool();
    return *pool;
}

void WorkerPool::shutdown() {
    std::lock_guard<std::mutex> lock(poolMutex);
    delete pool;   // joins the workers; a later step creates a fresh pool
    pool = nullptr;
}

WorkerPool::WorkerPool() {
    // SB_PHYSICS_THREADS overrides the default (all cores but one, at most three workers: the
    // physics step rarely has more than a few awake cars, and the main thread needs a core).
    std::size_t count = 0;
    const unsigned hw = std::thread::hardware_concurrency();
    if (hw > 2) count = std::min<std::size_t>(hw - 2, 3);
    if (const char* env = std::getenv("SB_PHYSICS_THREADS")) count = static_cast<std::size_t>(std::max(0, std::atoi(env) - 1));
    for (std::size_t i = 0; i < count; ++i) threads_.emplace_back([this] { loop(); });
}

WorkerPool::~WorkerPool() {
    stop_ = true;
    generation_.fetch_add(1, std::memory_order_release);
    generation_.notify_all();
    for (std::thread& t : threads_) t.join();
}

void WorkerPool::work() {
    for (;;) {
        const std::size_t i = next_.fetch_add(1, std::memory_order_relaxed);
        if (i >= n_) break;
        fn_(ctx_, i);
    }
}

void WorkerPool::dispatch(std::size_t n) {
    n_ = n;
    next_.store(0, std::memory_order_relaxed);
    acks_.store(0, std::memory_order_relaxed);
    generation_.fetch_add(1, std::memory_order_release);
    generation_.notify_all();
    work();
    // Every worker acknowledges the job before the next one may reuse its fields.
    for (int spin = 0; acks_.load(std::memory_order_acquire) < threads_.size(); ++spin) {
        if (spin < 4096) SB_PAUSE();
        else std::this_thread::yield();
    }
}

void WorkerPool::loop() {
    // Start from generation 0, not the current value: a job dispatched before this thread got
    // here must still be seen (the caller waits for every worker's acknowledgement).
    std::uint64_t seen = 0;
    for (;;) {
        std::uint64_t now = generation_.load(std::memory_order_acquire);
        // Between physics steps the next job usually follows within microseconds: spin a little
        // before sleeping on the counter.
        for (int spin = 0; now == seen && spin < 300; ++spin) {
            SB_PAUSE();
            now = generation_.load(std::memory_order_acquire);
        }
        while (now == seen) {
            generation_.wait(seen, std::memory_order_acquire);
            now = generation_.load(std::memory_order_acquire);
        }
        seen = now;
        if (stop_) return;
        work();
        acks_.fetch_add(1, std::memory_order_release);
    }
}

}  // namespace sb::detail
