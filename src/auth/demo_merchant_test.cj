package juxiaobao.auth

import juxiaobao.model.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DemoMerchantTests {
    @TestCase
    func createsBoundAccountAndKeepsItAcrossRestarts() {
        let repo = AuthTestRepository()
        repo.data.restaurants = [Restaurant(id: "sample", restaurantCode: "LAOXIANGJI")]
        ensureDemoMerchant(repo).unwrap()
        let first = repo.read()
        @Expect(first.merchants.size, 1)
        @Expect(first.restaurants[0].ownerId, first.merchants[0].id)
        @Expect(first.merchants[0].restaurantId, Some("sample"))
        @Expect(AuthService(repo).login(AccountKind.Merchant, "admin", "88888888").isOk(), true)
        let digest = first.merchants[0].passwordHash.toJson().toString()
        ensureDemoMerchant(repo).unwrap()
        @Expect(repo.read().merchants.size, 1)
        @Expect(repo.read().merchants[0].passwordHash.toJson().toString(), digest)
    }
    @TestCase
    func existingAdminKeepsPasswordAndOtherOwnersArePreserved() {
        let repo = AuthTestRepository()
        let auth = AuthService(repo)
        let admin = auth.register(AccountKind.Merchant, "admin", "existing-password").unwrap()
        repo.data.restaurants = [Restaurant(id: "sample", restaurantCode: "LAOXIANGJI")]
        ensureDemoMerchant(repo).unwrap()
        @Expect(auth.login(AccountKind.Merchant, "admin", "existing-password").isOk(), true)
        @Expect(repo.read().restaurants[0].ownerId, admin.id)
        repo.data.restaurants[0].ownerId = "another-owner"
        ensureDemoMerchant(repo).unwrap()
        @Expect(repo.read().restaurants[0].ownerId, "another-owner")
    }
    @TestCase
    func noSampleOrAdminWithAnotherRestaurantDoesNotCreateOrRebind() {
        let repo = AuthTestRepository()
        ensureDemoMerchant(repo).unwrap()
        @Expect(repo.read().merchants.size, 0)
        let admin = AuthService(repo).register(AccountKind.Merchant, "admin", "existing-password").unwrap()
        repo.data.restaurants = [Restaurant(id: "own", ownerId: admin.id, restaurantCode: "OTHER"),
            Restaurant(id: "sample", restaurantCode: "LAOXIANGJI")]
        ensureDemoMerchant(repo).unwrap()
        @Expect(repo.read().restaurants[1].ownerId, "")
        @Expect(repo.read().merchants.size, 1)
    }
}
