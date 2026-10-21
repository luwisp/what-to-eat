package juxiaobao.platform

import std.unittest.*
import std.unittest.testmacro.*

@Test
class RouterTests {
    @TestCase
    func pathParametersMatchWholeSegments() {
        let params = matchRoutePath("/__probe/items/:id", "/__probe/items/dish-1")
        @Expect(params.isSome(), true)
        if (let Some(values) <- params) { @Expect(values["id"], "dish-1") }
        @Expect(matchRoutePath("/__probe/items/:id", "/__probe/items").isSome(), false)
    }
}
