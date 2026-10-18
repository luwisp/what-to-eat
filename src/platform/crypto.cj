package huaiwei.platform

foreign func EVP_sha256(): CPointer<Unit>
foreign func PKCS5_PBKDF2_HMAC(password: CPointer<UInt8>, passwordLength: Int32,
    salt: CPointer<UInt8>, saltLength: Int32, iterations: Int32,
    digest: CPointer<Unit>, outputLength: Int32, output: CPointer<UInt8>): Int32

// A narrow binding to OpenSSL's mature implementation, not a password algorithm.
// Authentication owns salt generation, production work factor and stored format.
public func pbkdf2Sha256(password: Array<UInt8>, salt: Array<UInt8>, iterations: Int32): Array<UInt8> {
    if (iterations <= 0 || password.size > Int64(Int32.Max) || salt.size > Int64(Int32.Max)) {
        throw IllegalArgumentException("Invalid PBKDF2 parameters")
    }
    let output = Array<UInt8>(32, repeat: 0)
    unsafe {
        let passHandle = acquireArrayRawData(password)
        let saltHandle = acquireArrayRawData(salt)
        let outputHandle = acquireArrayRawData(output)
        try {
            if (PKCS5_PBKDF2_HMAC(passHandle.pointer, Int32(password.size),
                saltHandle.pointer, Int32(salt.size), iterations, EVP_sha256(),
                32, outputHandle.pointer) != 1) {
                throw Exception("OpenSSL PBKDF2 failed")
            }
        } finally {
            releaseArrayRawData(outputHandle)
            releaseArrayRawData(saltHandle)
            releaseArrayRawData(passHandle)
        }
    }
    return output
}
