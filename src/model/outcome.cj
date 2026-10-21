package juxiaobao.model

public class DomainError {
    public let code: String
    public let message: String
    public let status: UInt16
    public init(code: String, message: String, status!: UInt16 = 400) {
        this.code = code
        this.message = message
        this.status = status
    }
}

public enum Outcome<T> {
    Ok(T) | Err(DomainError)

    public func isOk(): Bool {
        match (this) { case Ok(_) => true; case Err(_) => false }
    }

    public func unwrap(): T {
        match (this) { case Ok(value) => value; case Err(e) => throw Exception("${e.code}: ${e.message}") }
    }
}
