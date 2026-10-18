package huaiwei.platform

import std.time.*

public interface Clock {
    func wallMillis(): Int64
    func monotonicMillis(): Int64
}

public class Deadline {
    let clock: Clock
    let startedAt: Int64
    let budgetMillis: Int64

    public init(clock: Clock, budgetMillis: Int64) {
        this.clock = clock
        this.startedAt = clock.monotonicMillis()
        this.budgetMillis = if (budgetMillis < 0) { 0 } else { budgetMillis }
    }

    public func remainingMillis(): Int64 {
        let elapsed = clock.monotonicMillis() - startedAt
        if (elapsed <= 0) { return budgetMillis }
        if (elapsed >= budgetMillis) { return 0 }
        return budgetMillis - elapsed
    }
}

public class SystemClock <: Clock {
    let origin = MonoTime.now()
    public func wallMillis(): Int64 { DateTime.nowUTC().toUnixTimeStamp().toMilliseconds() }
    public func monotonicMillis(): Int64 { (MonoTime.now() - origin).toMilliseconds() }
}
