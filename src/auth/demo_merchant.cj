package juxiaobao.auth

import juxiaobao.model.*
import juxiaobao.store.*
import juxiaobao.platform.*

class DemoMerchantSeed {
    var message = ""
}

public func ensureDemoMerchant(repository: Repository): Outcome<String> {
    let existing = repository.read()
    if (!existing.restaurants.any({r => r.restaurantCode == "LAOXIANGJI"})) {
        return Outcome.Ok("")
    }
    let seed = DemoMerchantSeed()
    let result = repository.transact({db =>
        let restaurant = db.restaurants.filter({r => r.restaurantCode == "LAOXIANGJI"})[0]
        let admins = db.merchants.filter({m => m.login == "admin"})
        if (!restaurant.ownerId.isEmpty()) {
            if (admins.isEmpty() || restaurant.ownerId != admins[0].id) {
                seed.message = "LAOXIANGJI 已有商家归属，跳过默认演示账号"
                return Outcome<DatabaseSnapshot>.Ok(db)
            }
            if (admins[0].restaurantId == Some(restaurant.id)) {
                return Outcome<DatabaseSnapshot>.Ok(db)
            }
        }
        if (!admins.isEmpty() &&
            (db.restaurants.any({r => r.id != restaurant.id && r.ownerId == admins[0].id}) ||
             (admins[0].restaurantId.isSome() && admins[0].restaurantId != Some(restaurant.id)))) {
            seed.message = "admin 已绑定其他餐馆，跳过 LAOXIANGJI 默认绑定"
            return Outcome<DatabaseSnapshot>.Ok(db)
        }
        let merchant = if (admins.isEmpty()) {
            let created = MerchantAccount(id: randomToken(), login: "admin", passwordHash: hashPassword("88888888"),
                createdAt: SystemClock().wallMillis())
            db.merchants = db.merchants.concat([created])
            seed.message = "演示商家 admin 已创建并绑定 LAOXIANGJI"
            created
        } else {
            seed.message = "LAOXIANGJI 已绑定现有 admin，保留原密码"
            admins[0]
        }
        restaurant.ownerId = merchant.id
        merchant.restaurantId = Some(restaurant.id)
        Outcome<DatabaseSnapshot>.Ok(db)
    })
    match (result) {
        case Ok(_) => Outcome.Ok(seed.message)
        case Err(error) => Outcome.Err(error)
    }
}
