package huaiwei.model

// Services implement these narrow ports; composition owns concrete dependencies.
public interface CatalogReader {
    func getMenu(restaurantCode: String): Outcome<MenuSnapshot>
}

public interface IdentityResolver {
    func resolve(cookies: String): Actor
    func ensureVisitor(cookies: String): Outcome<VisitorSession>
}

public enum AccountKind {
    User | Merchant
    public func toWire(): String {
        match (this) { case User => "user"; case Merchant => "merchant" }
    }
}

public enum RuleAdjustment {
    AddSoup
}

public enum JobStatus {
    Started(RecommendationJob) | InProgress(RecommendationJob)
}
