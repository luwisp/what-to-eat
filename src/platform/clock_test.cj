package huaiwei.platform

import std.unittest.*
import std.unittest.testmacro.*

class ManualClock <: Clock {
    public var tick: Int64 = 100
    public var wall: Int64 = 100000
    public func wallMillis(): Int64 { wall }
    public func monotonicMillis(): Int64 { tick }
}

@Test
class PlatformTests {
    @TestCase
    func deadlineUsesMonotonicTime() {
        let clock = ManualClock()
        let deadline = Deadline(clock, 30000)
        @Expect(deadline.remainingMillis(), 30000)
        clock.tick = 12100
        clock.wall = 1
        @Expect(deadline.remainingMillis(), 18000)
    }

    @TestCase
    func deadlineNeverGoesNegative() {
        let clock = ManualClock()
        let deadline = Deadline(clock, 30000)
        clock.tick = 40100
        @Expect(deadline.remainingMillis(), 0)
    }
}
