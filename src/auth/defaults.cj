package huaiwei.auth

import huaiwei.model.*
import huaiwei.store.*
import huaiwei.platform.*

public class DefaultSettingsService {
    let repository: Repository
    let clock: Clock
    public init(repository: Repository, clock!: Clock = SystemClock()) {
        this.repository = repository
        this.clock = clock
    }
    public func get(actor: Actor): Outcome<UserDefaultSettings> {
        let db = repository.read()
        if (!authorized(db, actor)) {
            return unauthorizedDefaults()
        }
        let id = actor.userId.getOrThrow()
        for (s in db.defaultSettings) {
            if (s.userId == id) {
                return Outcome.Ok(s)
            }
        }
        Outcome.Ok(UserDefaultSettings(userId: id))
    }
    public func put(actor: Actor, settings: UserDefaultSettings): Outcome<UserDefaultSettings> {
        if (actor.userId.isNone()) {
            return unauthorizedDefaults()
        }
        if (!validSettings(settings)) {
            return Outcome.Err(DomainError("INVALID_INPUT", "默认设置无效"))
        }
        // Copy only long-term fields. Authorization never uses settings.userId.
        let value = UserDefaultSettings(appetite: settings.appetite, userId: actor.userId.getOrThrow(), allergens: settings.allergens.clone(),
            avoidFoods: settings.avoidFoods.clone(), dietMode: settings.dietMode, maxSpiceLevel: settings.maxSpiceLevel,
            tastePreferences: settings.tastePreferences.clone(), updatedAt: clock.wallMillis())
        let result = repository.transact(
            {
                db =>
                    if (!authorized(db, actor)) {
                        return Outcome<DatabaseSnapshot>.Err(DomainError("UNAUTHENTICATED", "请先登录", status: 401))
                    }
                    db.defaultSettings = db.defaultSettings.filter({s => s.userId != value.userId}).concat([value])
                    Outcome<DatabaseSnapshot>.Ok(db)
            }
        )
        match (result) {
            case Ok(_) => Outcome.Ok(value);
            case Err(e) => Outcome.Err(e)
        }
    }
}

func authorized(db: DatabaseSnapshot, actor: Actor): Bool {
    actor.userId.isSome() && db.users.any({a => Some(a.id) == actor.userId})
}

func unauthorizedDefaults(): Outcome<UserDefaultSettings> {
    Outcome.Err(DomainError("UNAUTHENTICATED", "请先登录", status: 401))
}

func validSettings(s: UserDefaultSettings): Bool {
    if (!["small","normal","large","extraLarge"].contains(s.appetite)) { return false }
    if (s.dietMode != "none" && s.dietMode != "ovoLacto" && s.dietMode != "plant") {
        return false
    }
    if (let Some(level) <- s.maxSpiceLevel) {
        if (level < 0 || level > 3) {
            return false
        }
    }
    for (values in [s.allergens, s.avoidFoods, s.tastePreferences]) {
        if (values.size > 100) {
            return false
        }
        for (value in values) {
            if (value.trimAscii().isEmpty() || value.size > 256) {
                return false
            }
        }
    }
    true
}
